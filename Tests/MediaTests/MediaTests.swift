import DOM
import EngineCore
import Foundation
import HTML
import Media
import Testing

@Test func mediaKindDetection() {
  #expect(MediaFormat.kind(of: URL(string: "https://example.test/v.m3u8")!) == .hls)
  #expect(
    MediaFormat.kind(
      of: URL(string: "https://example.test/v.mp4")!, mimeType: "video/mp4") == .progressive)
  #expect(
    MediaFormat.kind(
      of: URL(string: "https://example.test/s")!, mimeType: "application/x-mpegurl") == .hls)
  #expect(MediaFormat.supportedSchemes(URL(string: "https://example.test/v.mp4")!))
  #expect(MediaFormat.supportedSchemes(URL(fileURLWithPath: "/tmp/v.mp4")))
  #expect(!MediaFormat.supportedSchemes(URL(string: "blob:https://example.test/x")!))
  #expect(!MediaFormat.supportedSchemes(URL(string: "ftp://example.test/v.mp4")!))
}

@Test func mediaCapabilityReport() {
  let capability = MediaFormat.currentCapability()
  #expect(capability.hlsPlayback)
  #expect(!capability.mediaSourceExtensions)
  #expect(!capability.protectedPlayback)
}

@Test func mediaRegistryDiscoversElements() async throws {
  let registry = MediaRegistry()
  let document = HTMLParser.parse(
    "<html><body><video src=\"v.mp4\"></video><audio><source src=\"a.mp3\"></audio></body></html>"
  ).document
  let page = PageID(rawValue: 7)
  let found = await registry.sync(
    pageID: page, document: document, baseURL: URL(string: "https://example.test/")!)
  #expect(found.count == 2)
  #expect(await registry.elements(pageID: page).count == 2)
  await registry.removePage(page)
  #expect(await registry.elements(pageID: page).isEmpty)
}

private func fixture(_ name: String) -> URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fixtures/media/\(name)")
}

private func playAndAwaitTime(
  registry: MediaRegistry, node: NodeID, minimum: Double = 0.4, timeout: Double = 15
) async throws -> PlayerBackend.MediaElementSnapshot {
  await registry.play(node)
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    let element = await registry.element(node)
    let (snap, _, _) = element?.backend.state() ?? (PlayerBackend.MediaElementSnapshot(), 0, nil)
    if snap.currentTime >= minimum && snap.statusReady { return snap }
    try await Task.sleep(for: .milliseconds(100))
  }
  throw MediaProbeError.timeout
}

private enum MediaProbeError: Error {
  case timeout
}

@Test func progressivePlaybackAdvancesTimeAndDeliversFrames() async throws {
  let registry = MediaRegistry()
  let url = fixture("sample.mp4")
  let document = HTMLParser.parse(
    "<html><body><video src=\"\(url.absoluteString)\"></video></body></html>"
  ).document
  let page = PageID(rawValue: 11)
  let found = await registry.sync(
    pageID: page, document: document, baseURL: URL(string: "https://example.test/")!)
  let node = try #require(found.first)
  let snap = try await playAndAwaitTime(registry: registry, node: node)
  #expect(snap.duration > 3.5 && snap.duration < 4.5)
  #expect(snap.videoWidth == 320 && snap.videoHeight == 240)
  #expect(!snap.audioTracks.isEmpty)
  await registry.pause(node)
  for _ in 0..<10 {
    await registry.pollFrames(node)
    try await Task.sleep(for: .milliseconds(100))
  }
  let state = await registry.snapshot(node, tag: "video")
  #expect(state.deliveredFrames > 0)
  #expect((state.lastFrameTime ?? -1) >= 0)
  #expect(await registry.seek(node, to: 1.0))
  await registry.pause(node)
  await registry.removePage(page)
}

@Test func hlsPlaybackAdvancesTime() async throws {
  try await withMediaServer { base in
    let registry = MediaRegistry()
    let document = HTMLParser.parse(
      "<html><body><video src=\"\(base)/sample.m3u8\"></video></body></html>"
    ).document
    let page = PageID(rawValue: 12)
    let found = await registry.sync(
      pageID: page, document: document, baseURL: URL(string: "\(base)/")!)
    let node = try #require(found.first)
    let snap = try await playAndAwaitTime(registry: registry, node: node)
    #expect(snap.duration > 3.5 && snap.duration < 4.5)
    await registry.pause(node)
    await registry.removePage(page)
  }
}

private func withMediaServer(
  _ body: (String) async throws -> Void
) async throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/media").path
  var lastError: Error?
  for port in [18711, 18712, 18713] {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = ["-m", "http.server", String(port), "--directory", root]
    server.standardOutput = FileHandle.nullDevice
    server.standardError = FileHandle.nullDevice
    try server.run()
    defer {
      if server.isRunning { server.terminate() }
    }
    if await waitForPort(port, timeout: 5) {
      do {
        try await body("http://127.0.0.1:\(port)")
        return
      } catch {
        lastError = error
      }
    } else {
      server.terminate()
      lastError = MediaProbeError.timeout
    }
  }
  throw lastError ?? MediaProbeError.timeout
}

private func waitForPort(_ port: Int, timeout: Double) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    task.arguments = ["-z", "127.0.0.1", String(port)]
    try? task.run()
    task.waitUntilExit()
    if task.terminationStatus == 0 { return true }
    try? await Task.sleep(for: .milliseconds(100))
  }
  return false
}

@Test func unsupportedSourceReportsNoSource() async throws {
  let registry = MediaRegistry()
  let document = HTMLParser.parse(
    "<html><body><video src=\"ftp://example.test/v.mp4\"></video></body></html>"
  ).document
  let page = PageID(rawValue: 13)
  let found = await registry.sync(
    pageID: page, document: document, baseURL: URL(string: "https://example.test/")!)
  let node = try #require(found.first)
  let state = await registry.snapshot(node, tag: "video")
  #expect(state.networkState == .noSource)
  #expect(state.currentSrc == nil)
  await registry.removePage(page)
}

@Test func canPlayTypeMatrix() {
  #expect(MediaFormat.canPlayType(mime: "video/mp4", tag: "video") == "probably")
  #expect(MediaFormat.canPlayType(mime: "video/mp4", tag: "audio") == "")
  #expect(MediaFormat.canPlayType(mime: "audio/mpeg", tag: "audio") == "probably")
  #expect(
    MediaFormat.canPlayType(mime: "application/x-mpegurl", tag: "video") == "probably")
  #expect(MediaFormat.canPlayType(mime: "video/webm", tag: "video") == "maybe")
  #expect(MediaFormat.canPlayType(mime: "application/octet-stream", tag: "video") == "")
}
