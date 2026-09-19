import Foundation

public enum JSTokenKind: Equatable {
  case number(Double)
  case bigint(String)
  case string(String)
  case regex(pattern: String, flags: String)
  case templateChunk(String)
  case identifier(String)
  case keyword(String)
  case symbol(String)
  case eof
}

public struct JSToken: Equatable {
  public var kind: JSTokenKind
  public var offset: Int
  public var lineTerminatorBefore: Bool

  public init(kind: JSTokenKind, offset: Int, lineTerminatorBefore: Bool = false) {
    self.kind = kind
    self.offset = offset
    self.lineTerminatorBefore = lineTerminatorBefore
  }
}
