import AetherNetworkHardening
import CSS
import DOM
import Diagnostics
import Display
import EngineCore
import Foundation
import Graphics
import HTML
import Images
import Layout
import Networking
import Storage
import Style
import Text
import WebAPI
import WebSecurity

public struct NavigationPipeline: Sendable {
  public let network: NetworkSession
  public let metricsCollector: MetricsCollector
  private let navigationCounter: AtomicCounter
  private let documentCounter: AtomicCounter

  public init(
    network: NetworkSession, metricsCollector: MetricsCollector,
    navigationCounter: AtomicCounter = AtomicCounter(),
    documentCounter: AtomicCounter = AtomicCounter()
  ) {
    self.network = network
    self.metricsCollector = metricsCollector
    self.navigationCounter = navigationCounter
    self.documentCounter = documentCounter
  }

  public func load(_ url: URL, viewport: Size) async throws -> LoadedPage {
    try await load(HTTPRequest(url: url), viewport: viewport)
  }

  public func load(_ request: HTTPRequest, viewport: Size) async throws -> LoadedPage {
    let totalClock = ContinuousClock()
    let totalStart = totalClock.now
    let navigationID = NavigationID(rawValue: navigationCounter.next())

    switch NavigationPolicy.decideNavigation(from: nil, to: request.url) {
    case .deny(let reason): throw NavigationError.network(reason)
    case .download: throw NavigationError.network("navigation target is a download")
    case .allow: break
    }

    let (response, networkMilliseconds) = try await MetricClock.asyncMilliseconds {
      try await network.fetch(request)
    }
    let html = HTMLParser.decodeBytes(response.body)

    let (parseResult, parseMilliseconds) = MetricClock.milliseconds {
      HTMLParser.parse(html, documentID: DocumentID(rawValue: documentCounter.next()))
    }
    let document = parseResult.document
    let resources = ResourceDiscovery.discover(in: document, baseURL: response.url)
    let pageOrigin = Origin(url: response.url) ?? .opaque
    let csp = ContentSecurityPolicy.parse(headers: response.headers) ?? ContentSecurityPolicy()
    async let externalSheetsTask = loadStylesheets(resources.stylesheets, pageURL: response.url)
    async let scriptsTask = loadScripts(
      resources.scripts, pageURL: response.url, csp: csp, pageOrigin: pageOrigin)
    async let imagesTask = loadImages(resources.images, pageURL: response.url)
    let externalSheets = await externalSheetsTask
    var sheets: [Stylesheet] = []
    var sourceOrder = 0
    for css in externalSheets {
      let sheet = CSSParser.parse(css, startingSourceOrder: sourceOrder)
      sourceOrder += sheet.rules.count
      sheets.append(sheet)
    }
    for inline in resources.inlineStyles {
      let sheet = CSSParser.parse(inline, startingSourceOrder: sourceOrder)
      sourceOrder += sheet.rules.count
      sheets.append(sheet)
    }

    let (scripts, scriptErrors) = await scriptsTask
    let (images, imageErrors) = await imagesTask

    let (styled, styleMilliseconds) = MetricClock.milliseconds {
      StyleResolver.resolve(document: document, stylesheets: sheets, viewport: viewport)
    }
    let (layout, layoutMilliseconds) = MetricClock.milliseconds {
      LayoutEngine().layout(styled, viewport: viewport)
    }
    let (displayList, displayListMilliseconds) = MetricClock.milliseconds {
      DisplayListBuilder.build(document: document, layout: layout, images: images)
    }

    let totalDuration = totalStart.duration(to: totalClock.now)
    let totalMilliseconds =
      Double(totalDuration.components.seconds) * 1000 + Double(totalDuration.components.attoseconds)
      / 1e15
    let metrics = EngineMetrics(
      networkMilliseconds: networkMilliseconds,
      parseMilliseconds: parseMilliseconds,
      styleMilliseconds: styleMilliseconds,
      layoutMilliseconds: layoutMilliseconds,
      displayListMilliseconds: displayListMilliseconds,
      totalMilliseconds: totalMilliseconds,
      domNodes: document.nodeCount,
      displayCommands: displayList.commands.count,
      responseBytes: response.body.count
    )
    await metricsCollector.record(metrics, key: navigationID.description)

    return LoadedPage(
      navigationID: navigationID,
      url: response.url,
      statusCode: response.statusCode,
      title: document.documentTitle(),
      document: document,
      styledDocument: styled,
      layout: layout,
      displayList: displayList,
      metrics: metrics,
      stylesheets: sheets,
      images: images,
      scripts: scripts,
      scriptErrors: scriptErrors,
      imageErrors: imageErrors
    )
  }

  public func relayout(_ page: LoadedPage, viewport: Size) -> LoadedPage {
    let styled = StyleResolver.resolve(
      document: page.document, stylesheets: page.stylesheets, viewport: viewport)
    let layout = LayoutEngine().layout(styled, viewport: viewport)
    let display = DisplayListBuilder.build(
      document: page.document, layout: layout, images: page.images)
    var updated = page
    updated.styledDocument = styled
    updated.layout = layout
    updated.displayList = display
    updated.title = page.document.documentTitle()
    return updated
  }

  private func subresourceError(_ url: URL, pageURL: URL) -> String? {
    if !NavigationPolicy.allowsSubresource(url) {
      return "Subresource scheme blocked \(url.absoluteString)"
    }
    if MixedContent.decision(pageURL: pageURL, resourceURL: url) == .block {
      return "Mixed content blocked \(url.absoluteString)"
    }
    return nil
  }

  private func loadScripts(
    _ scripts: [DiscoveredScript], pageURL: URL, csp: ContentSecurityPolicy, pageOrigin: Origin
  ) async -> ([String], [String]) {
    var sources: [String] = []
    var errors: [String] = []
    sources.reserveCapacity(scripts.count)
    for script in scripts {
      switch script {
      case .inline(let source):
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        guard csp.allowsScript(origin: pageOrigin, source: nil, inline: true) else {
          errors.append("Inline script blocked by content-security-policy")
          continue
        }
        sources.append(source)
      case .external(let url):
        if let blocked = subresourceError(url, pageURL: pageURL) {
          errors.append(blocked)
          continue
        }
        guard csp.allowsScript(origin: pageOrigin, source: url, inline: false) else {
          errors.append("Script blocked by content-security-policy \(url.absoluteString)")
          continue
        }
        do {
          let response = try await network.fetch(url)
          try ResponseContentGuard.validate(
            status: response.statusCode, headers: response.headers, destination: .script)
          if let source = response.text {
            sources.append(source)
          } else {
            errors.append("Script body could not be decoded: \(url.absoluteString)")
          }
        } catch {
          errors.append("Script load failed \(url.absoluteString): \(error)")
        }
      }
    }
    return (sources, errors)
  }

  private func loadImages(_ images: [DiscoveredImage], pageURL: URL) async -> ([NodeID: DecodedImage], [String]) {
    var allowed: [DiscoveredImage] = []
    var blocked: [String] = []
    for image in images {
      if let reason = subresourceError(image.url, pageURL: pageURL) {
        blocked.append(reason)
      } else {
        allowed.append(image)
      }
    }
    return await withTaskGroup(
      of: (NodeID, URL, Result<DecodedImage, Error>).self,
      returning: ([NodeID: DecodedImage], [String]).self
    ) { group in
      let loader = ImageLoader(network: network)
      for image in allowed {
        group.addTask {
          do { return (image.nodeID, image.url, .success(try await loader.load(image.url))) } catch
          { return (image.nodeID, image.url, .failure(error)) }
        }
      }
      var decoded: [NodeID: DecodedImage] = [:]
      var errors: [String] = blocked
      for await (nodeID, url, result) in group {
        switch result {
        case .success(let image): decoded[nodeID] = image
        case .failure(let error): errors.append("Image load failed \(url.absoluteString): \(error)")
        }
      }
      return (decoded, errors.sorted())
    }
  }

  private func loadStylesheets(_ urls: [URL], pageURL: URL) async -> [String] {
    let allowed = urls.filter { subresourceError($0, pageURL: pageURL) == nil }
    let requests = allowed.enumerated().map {
      ResourceRequest(key: String($0.offset), url: $0.element)
    }
    let results = await ResourceLoader(network: network).load(requests)
    return allowed.indices.compactMap { index in
      guard let result = results[String(index)], case .success(let response) = result else {
        return nil
      }
      guard (try? ResponseContentGuard.validate(
        status: response.statusCode, headers: response.headers, destination: .stylesheet)) != nil
      else { return nil }
      return response.text
    }
  }
}
