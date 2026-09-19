import Foundation

public enum MixedContentDecision: Hashable, Sendable {
  case allow
  case block
}

public enum MixedContent {
  public static func decision(pageURL: URL, resourceURL: URL) -> MixedContentDecision {
    let pageScheme = pageURL.scheme?.lowercased()
    let resourceScheme = resourceURL.scheme?.lowercased()
    guard pageScheme == "https" else { return .allow }
    if resourceScheme == "https" || resourceScheme == "wss" || resourceScheme == "data"
      || resourceScheme == "blob"
    {
      return .allow
    }
    return .block
  }

  public static func isActiveContent(tag: String) -> Bool {
    ["script", "link", "frame", "iframe", "fetch", "websocket", "style"].contains(
      tag.lowercased())
  }
}

public enum NavigationDecision: Hashable, Sendable {
  case allow
  case deny(String)
  case download
}

public enum NavigationPolicy {
  public static let topLevelSchemes: Set<String> = ["http", "https", "about", "file"]
  public static let subresourceSchemes: Set<String> = [
    "http", "https", "data", "blob", "file",
  ]

  public static func decideNavigation(from current: URL?, to target: URL) -> NavigationDecision {
    guard let scheme = target.scheme?.lowercased() else {
      return .deny("URL without scheme cannot be navigated")
    }
    if scheme == "javascript" { return .deny("javascript: navigation is not executed") }
    if scheme == "about" || scheme == "data" || scheme == "blob" {
      if target.absoluteString.lowercased().hasPrefix("about:blank") { return .allow }
      return .deny("opaque scheme cannot be a top-level navigation target")
    }
    if !topLevelSchemes.contains(scheme) { return .deny("scheme \(scheme) is not navigable") }
    if scheme == "file" {
      if current?.scheme?.lowercased() != "file" {
        return .deny("remote pages cannot navigate to file: URLs")
      }
    }
    return .allow
  }

  public static func allowsSubresource(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    if scheme == "javascript" { return false }
    return subresourceSchemes.contains(scheme)
  }

  public static func isDownload(navigation: Bool, mimeType: String?, disposition: String?) -> Bool {
    if let disposition = disposition?.lowercased(), disposition.contains("attachment") {
      return true
    }
    guard let mime = mimeType?.lowercased() else { return false }
    return mime == "application/octet-stream" || mime.hasPrefix("application/zip")
  }
}

public enum FramePolicy {
  public static func canScriptAccess(frame: Origin, from accessor: Origin) -> Bool {
    accessor.isSameOrigin(as: frame)
  }

  public static func canNavigate(frame: Origin, from initiator: Origin, isAncestor: Bool) -> Bool {
    if initiator.isSameOrigin(as: frame) { return true }
    return isAncestor
  }

  public static func canEmbed(parent: Origin, child: URL, frameAncestors: [String]) -> Bool {
    if frameAncestors.isEmpty { return true }
    if frameAncestors.contains("'none'") { return false }
    if frameAncestors.contains("'self'") {
      if let childOrigin = Origin(url: child), childOrigin.isSameOrigin(as: parent) {
        return true
      }
    }
    for entry in frameAncestors {
      if entry == "*" { return true }
      if let host = child.host?.lowercased(), host == entry.lowercased() { return true }
    }
    return false
  }
}

public enum DownloadDecision: Hashable, Sendable {
  case allow
  case deny(String)
}

public enum DownloadPolicy {
  public static func decide(url: URL, from origin: Origin?) -> DownloadDecision {
    guard let scheme = url.scheme?.lowercased() else {
      return .deny("URL without scheme cannot be downloaded")
    }
    if ["javascript", "about"].contains(scheme) {
      return .deny("scheme \(scheme) cannot produce a download")
    }
    if scheme == "file", origin?.scheme != "file" {
      return .deny("remote pages cannot trigger file: downloads")
    }
    if !["http", "https", "blob", "data", "file"].contains(scheme) {
      return .deny("scheme \(scheme) cannot produce a download")
    }
    return .allow
  }
}

public enum PermissionBoundary {
  public static func allows(
    _ permission: WebPermission, origin: Origin, isTopLevel: Bool
  ) -> Bool {
    switch permission {
    case .camera, .microphone, .geolocation:
      return origin.isPotentiallyTrustworthy && isTopLevel
    case .notifications:
      return origin.isPotentiallyTrustworthy
    case .clipboardRead:
      return origin.isPotentiallyTrustworthy && isTopLevel
    case .clipboardWrite:
      return origin.isPotentiallyTrustworthy
    case .filesystem:
      return origin.isPotentiallyTrustworthy && isTopLevel
    }
  }
}
