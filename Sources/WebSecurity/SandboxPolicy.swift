import Foundation

public struct SandboxPolicy: Hashable, Sendable, Codable {
  public var allowScripts: Bool
  public var allowForms: Bool
  public var allowPopups: Bool
  public var allowTopNavigation: Bool
  public var allowDownloads: Bool

  public init(
    allowScripts: Bool = true, allowForms: Bool = true, allowPopups: Bool = false,
    allowTopNavigation: Bool = true, allowDownloads: Bool = true
  ) {
    self.allowScripts = allowScripts
    self.allowForms = allowForms
    self.allowPopups = allowPopups
    self.allowTopNavigation = allowTopNavigation
    self.allowDownloads = allowDownloads
  }
}
