import Foundation

public struct RGBAColor: Hashable, Sendable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = Self.clamp(red)
    self.green = Self.clamp(green)
    self.blue = Self.clamp(blue)
    self.alpha = Self.clamp(alpha)
  }

  public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
  public static let black = RGBAColor(red: 0, green: 0, blue: 0)
  public static let white = RGBAColor(red: 1, green: 1, blue: 1)
  public static let transparent = clear

  public var rgba8: (UInt8, UInt8, UInt8, UInt8) {
    (
      UInt8((red * 255).rounded()),
      UInt8((green * 255).rounded()),
      UInt8((blue * 255).rounded()),
      UInt8((alpha * 255).rounded())
    )
  }

  public static func parse(_ input: String) -> RGBAColor? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasPrefix("#") { return parseHex(String(value.dropFirst())) }
    if value.hasPrefix("rgb(") && value.hasSuffix(")") { return parseRGBFunction(value) }
    if value.hasPrefix("rgba(") && value.hasSuffix(")") { return parseRGBAFunction(value) }
    return named[value]
  }

  private static func clamp(_ value: Double) -> Double {
    min(1, max(0, value))
  }

  private static func parseHex(_ value: String) -> RGBAColor? {
    func byte(_ pair: Substring) -> Double? {
      guard let n = UInt8(pair, radix: 16) else { return nil }
      return Double(n) / 255
    }
    switch value.count {
    case 3, 4:
      let chars = Array(value)
      guard let r = UInt8(String(repeating: String(chars[0]), count: 2), radix: 16),
        let g = UInt8(String(repeating: String(chars[1]), count: 2), radix: 16),
        let b = UInt8(String(repeating: String(chars[2]), count: 2), radix: 16)
      else { return nil }
      let a =
        value.count == 4
        ? Double(UInt8(String(repeating: String(chars[3]), count: 2), radix: 16) ?? 255) / 255 : 1
      return RGBAColor(
        red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
    case 6, 8:
      let i = value.startIndex
      let p0 = value[i..<value.index(i, offsetBy: 2)]
      let p1s = value.index(i, offsetBy: 2)
      let p1 = value[p1s..<value.index(p1s, offsetBy: 2)]
      let p2s = value.index(i, offsetBy: 4)
      let p2 = value[p2s..<value.index(p2s, offsetBy: 2)]
      guard let r = byte(p0), let g = byte(p1), let b = byte(p2) else { return nil }
      if value.count == 8 {
        let p3s = value.index(i, offsetBy: 6)
        let p3 = value[p3s..<value.index(p3s, offsetBy: 2)]
        guard let a = byte(p3) else { return nil }
        return RGBAColor(red: r, green: g, blue: b, alpha: a)
      }
      return RGBAColor(red: r, green: g, blue: b)
    default:
      return nil
    }
  }

  private static func parseRGBFunction(_ value: String) -> RGBAColor? {
    let inner = value.dropFirst(4).dropLast()
    let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 3,
      let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2])
    else { return nil }
    return RGBAColor(red: r / 255, green: g / 255, blue: b / 255)
  }

  private static func parseRGBAFunction(_ value: String) -> RGBAColor? {
    let inner = value.dropFirst(5).dropLast()
    let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 4,
      let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]),
      let a = Double(parts[3])
    else { return nil }
    return RGBAColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
  }

  private static let named: [String: RGBAColor] = [
    "transparent": .clear,
    "black": .black,
    "white": .white,
    "red": RGBAColor(red: 1, green: 0, blue: 0),
    "green": RGBAColor(red: 0, green: 0.5, blue: 0),
    "blue": RGBAColor(red: 0, green: 0, blue: 1),
    "gray": RGBAColor(red: 0.5, green: 0.5, blue: 0.5),
    "grey": RGBAColor(red: 0.5, green: 0.5, blue: 0.5),
    "yellow": RGBAColor(red: 1, green: 1, blue: 0),
    "orange": RGBAColor(red: 1, green: 0.647, blue: 0),
    "purple": RGBAColor(red: 0.5, green: 0, blue: 0.5),
  ]
}
