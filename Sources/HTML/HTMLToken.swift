import Foundation

public struct HTMLAttributeToken: Hashable, Sendable {
  public var name: String
  public var value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public enum HTMLToken: Hashable, Sendable {
  case doctype(String)
  case startTag(name: String, attributes: [HTMLAttributeToken], selfClosing: Bool)
  case endTag(String)
  case comment(String)
  case character(String)
}
