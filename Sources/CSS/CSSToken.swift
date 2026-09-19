import Foundation

public enum CSSToken: Hashable, Sendable {
  case ident(String)
  case hash(String)
  case number(Double)
  case dimension(Double, String)
  case percentage(Double)
  case string(String)
  case colon
  case semicolon
  case comma
  case leftBrace
  case rightBrace
  case leftParen
  case rightParen
  case leftBracket
  case rightBracket
  case delimiter(Character)
  case whitespace
}
