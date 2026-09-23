import Foundation

public enum JSONValue: Sendable, Codable {
  case null
  case bool(Bool)
  case integer(Int64)
  case uint(UInt64)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(UInt64.self) {
      self = .uint(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .uint(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public var string: String? {
    if case .string(let value) = self { value } else { nil }
  }

  public var number: Double? {
    switch self {
    case .number(let value): value
    case .integer(let value): Double(value)
    case .uint(let value): Double(value)
    default: nil
    }
  }

  public var exactInt64: Int64? {
    switch self {
    case .integer(let value): value
    case .uint(let value): Int64(exactly: value)
    case .number(let value): Int64(exactly: value)
    default: nil
    }
  }

  public var exactUInt64: UInt64? {
    switch self {
    case .integer(let value): value >= 0 ? UInt64(value) : nil
    case .uint(let value): value
    case .number(let value): UInt64(exactly: value)
    default: nil
    }
  }

  public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
  public var object: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }
  public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
  public subscript(key: String) -> JSONValue? { object?[key] }
}

extension JSONValue: Hashable {
  public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): true
    case (.bool(let a), .bool(let b)): a == b
    case (.integer(let a), .integer(let b)): a == b
    case (.uint(let a), .uint(let b)): a == b
    case (.integer(let a), .uint(let b)): a >= 0 && UInt64(a) == b
    case (.uint(let a), .integer(let b)): b >= 0 && a == UInt64(b)
    case (.number(let a), .number(let b)): a == b
    case (.integer(let a), .number(let b)): Double(a) == b
    case (.number(let a), .integer(let b)): a == Double(b)
    case (.uint(let a), .number(let b)): Double(a) == b && UInt64(exactly: b) == a
    case (.number(let a), .uint(let b)): a == Double(b) && UInt64(exactly: a) == b
    case (.string(let a), .string(let b)): a == b
    case (.array(let a), .array(let b)): a == b
    case (.object(let a), .object(let b)): a == b
    default: false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .null:
      hasher.combine(0)
    case .bool(let value):
      hasher.combine(1)
      hasher.combine(value)
    case .integer(let value):
      hasher.combine(2)
      hasher.combine(value)
    case .uint(let value):
      if let exact = Int64(exactly: value) {
        hasher.combine(2)
        hasher.combine(exact)
      } else {
        hasher.combine(3)
        hasher.combine(Double(value))
      }
    case .number(let value):
      if let exact = Int64(exactly: value) {
        hasher.combine(2)
        hasher.combine(exact)
      } else {
        hasher.combine(3)
        hasher.combine(value)
      }
    case .string(let value):
      hasher.combine(4)
      hasher.combine(value)
    case .array(let value):
      hasher.combine(5)
      hasher.combine(value)
    case .object(let value):
      hasher.combine(6)
      hasher.combine(value)
    }
  }
}
