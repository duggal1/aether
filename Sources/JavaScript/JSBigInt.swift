import Foundation

enum JSBigInt {
  static func normalize(_ text: String) -> String {
    var work = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var negative = false
    if work.hasPrefix("-") {
      negative = true
      work = String(work.dropFirst())
    } else if work.hasPrefix("+") {
      work = String(work.dropFirst())
    }
    work = String(work.drop(while: { $0 == "0" }))
    if work.isEmpty { return "0" }
    return negative ? "-\(work)" : work
  }

  static func parse(_ value: JSValue) throws -> String {
    switch value {
    case .bigint(let text): return text
    case .number(let number):
      if number.isNaN || number.isInfinite {
        throw JSError.range("Cannot convert \(value) to BigInt")
      }
      if number.rounded() != number { throw JSError.range("Cannot convert \(value) to BigInt") }
      return normalize(String(Int64(number)))
    case .string(let text):
      let work = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if work.isEmpty { return "0" }
      var body = work
      var negative = false
      if body.hasPrefix("-") {
        negative = true
        body = String(body.dropFirst())
      } else if body.hasPrefix("+") {
        body = String(body.dropFirst())
      }
      if body.hasPrefix("0x") || body.hasPrefix("0X") {
        guard let raw = UInt64(body.dropFirst(2), radix: 16) else {
          throw JSError.syntax("Cannot convert \(text) to BigInt")
        }
        return normalize((negative ? "-" : "") + String(raw))
      }
      if body.hasPrefix("0b") || body.hasPrefix("0B") {
        guard let raw = UInt64(body.dropFirst(2), radix: 2) else {
          throw JSError.syntax("Cannot convert \(text) to BigInt")
        }
        return normalize((negative ? "-" : "") + String(raw))
      }
      if body.hasPrefix("0o") || body.hasPrefix("0O") {
        guard let raw = UInt64(body.dropFirst(2), radix: 8) else {
          throw JSError.syntax("Cannot convert \(text) to BigInt")
        }
        return normalize((negative ? "-" : "") + String(raw))
      }
      guard !body.isEmpty, body.allSatisfy({ $0.isNumber }) else {
        throw JSError.syntax("Cannot convert \(text) to BigInt")
      }
      return normalize(work)
    case .bool(let flag): return flag ? "1" : "0"
    case .null: throw JSError.type("Cannot convert null to BigInt")
    case .undefined: throw JSError.type("Cannot convert undefined to BigInt")
    case .symbol: throw JSError.type("Cannot convert Symbol to BigInt")
    case .object, .function: throw JSError.type("Cannot convert object to BigInt")
    }
  }

  static func compare(_ lhs: String, _ rhs: String) -> Int {
    let a = normalize(lhs)
    let b = normalize(rhs)
    if a == b { return 0 }
    let aNegative = a.hasPrefix("-")
    let bNegative = b.hasPrefix("-")
    if aNegative != bNegative { return aNegative ? -1 : 1 }
    let aDigits = aNegative ? String(a.dropFirst()) : a
    let bDigits = bNegative ? String(b.dropFirst()) : b
    if aDigits.count != bDigits.count {
      let order = aDigits.count < bDigits.count ? -1 : 1
      return aNegative ? -order : order
    }
    let order = aDigits < bDigits ? -1 : 1
    return aNegative ? -order : order
  }

  static func add(_ lhs: String, _ rhs: String) -> String {
    addSigned(normalize(lhs), normalize(rhs))
  }

  static func subtract(_ lhs: String, _ rhs: String) -> String {
    addSigned(normalize(lhs), negate(normalize(rhs)))
  }

  static func multiply(_ lhs: String, _ rhs: String) -> String {
    let a = normalize(lhs)
    let b = normalize(rhs)
    if a == "0" || b == "0" { return "0" }
    let negative = a.hasPrefix("-") != b.hasPrefix("-")
    let product = multiplyDigits(strip(a), strip(b))
    return negative ? "-\(product)" : product
  }

  static func divide(_ lhs: String, _ rhs: String) throws -> String {
    let b = normalize(rhs)
    if b == "0" { throw JSError.range("Division by zero") }
    let a = normalize(lhs)
    let negative = a.hasPrefix("-") != b.hasPrefix("-")
    let quotient = divideDigits(strip(a), strip(b))
    if quotient == "0" { return "0" }
    return negative ? "-\(quotient)" : quotient
  }

  static func remainder(_ lhs: String, _ rhs: String) throws -> String {
    let b = normalize(rhs)
    if b == "0" { throw JSError.range("Division by zero") }
    let a = normalize(lhs)
    let quotient = try divide(a, b)
    let product = multiply(quotient, b)
    return subtract(a, product)
  }

  static func power(_ base: String, _ exponent: String) throws -> String {
    if exponent.hasPrefix("-") { throw JSError.range("Negative BigInt exponent") }
    var result = "1"
    var factor = normalize(base)
    var count = normalize(exponent)
    while count != "0" {
      let half = try divide(count, "2")
      let doubled = multiply(half, "2")
      if doubled != count { result = multiply(result, factor) }
      count = half
      if count != "0" { factor = multiply(factor, factor) }
    }
    return result
  }

  static func negate(_ text: String) -> String {
    let value = normalize(text)
    if value == "0" { return "0" }
    return value.hasPrefix("-") ? String(value.dropFirst()) : "-\(value)"
  }

  static func bitwise(_ lhs: String, _ rhs: String, _ operation: String) -> String {
    let width = max(bitLength(strip(lhs)), bitLength(strip(rhs))) + 1
    let a = twosComplement(normalize(lhs), width: width)
    let b = twosComplement(normalize(rhs), width: width)
    var result = Array(repeating: Character("0"), count: width)
    for index in 0..<width {
      let x = a[a.index(a.startIndex, offsetBy: index)] == "1"
      let y = b[b.index(b.startIndex, offsetBy: index)] == "1"
      let bit: Bool
      switch operation {
      case "xor": bit = x != y
      case "or": bit = x || y
      default: bit = x && y
      }
      result[index] = bit ? "1" : "0"
    }
    return fromTwosComplement(String(result))
  }

  static func shift(_ lhs: String, _ rhs: String, right: Bool) throws -> String {
    let value = normalize(lhs)
    var amount = normalize(rhs)
    if amount.hasPrefix("-") {
      if right { return try shift(strip(value) == "0" ? "0" : value, negate(amount), right: false) }
      return "0"
    }
    guard let small = Int(amount), small >= 0 else {
      if right { return value.hasPrefix("-") ? "-1" : "0" }
      throw JSError.range("BigInt shift out of range")
    }
    if right {
      if small == 0 { return value }
      let divisor = powerOfTwo(small)
      let quotient = try? divide(strip(value), divisor)
      let magnitude = quotient ?? "0"
      if value.hasPrefix("-") {
        if magnitude == "0" { return "-1" }
        let product = multiply(magnitude, divisor)
        if product == strip(value) { return "-\(magnitude)" }
        return "-\(add(magnitude, "1"))"
      }
      return magnitude
    }
    if value == "0" { return "0" }
    let product = multiply(strip(value), powerOfTwo(small))
    return value.hasPrefix("-") ? "-\(product)" : product
  }

  private static func strip(_ text: String) -> String {
    text.hasPrefix("-") ? String(text.dropFirst()) : text
  }

  private static func addSigned(_ lhs: String, _ rhs: String) -> String {
    let aNegative = lhs.hasPrefix("-")
    let bNegative = rhs.hasPrefix("-")
    if aNegative == bNegative {
      let sum = addDigits(strip(lhs), strip(rhs))
      if sum == "0" { return "0" }
      return aNegative ? "-\(sum)" : sum
    }
    let comparison = compareDigits(strip(lhs), strip(rhs))
    if comparison == 0 { return "0" }
    if comparison > 0 {
      let difference = subtractDigits(strip(lhs), strip(rhs))
      return aNegative ? "-\(difference)" : difference
    }
    let difference = subtractDigits(strip(rhs), strip(lhs))
    return bNegative ? "-\(difference)" : difference
  }

  private static func compareDigits(_ lhs: String, _ rhs: String) -> Int {
    if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
    if lhs == rhs { return 0 }
    return lhs < rhs ? -1 : 1
  }

  private static func addDigits(_ lhs: String, _ rhs: String) -> String {
    let a = Array(lhs.reversed().map { Int(String($0)) ?? 0 })
    let b = Array(rhs.reversed().map { Int(String($0)) ?? 0 })
    var result: [Int] = []
    var carry = 0
    for index in 0..<max(a.count, b.count) {
      let sum = (index < a.count ? a[index] : 0) + (index < b.count ? b[index] : 0) + carry
      result.append(sum % 10)
      carry = sum / 10
    }
    while carry > 0 {
      result.append(carry % 10)
      carry /= 10
    }
    while result.count > 1 && result.last == 0 { result.removeLast() }
    return result.reversed().map(String.init).joined()
  }

  private static func subtractDigits(_ lhs: String, _ rhs: String) -> String {
    var result: [Int] = []
    let a = Array(lhs.reversed().map { Int(String($0)) ?? 0 })
    let b = Array(rhs.reversed().map { Int(String($0)) ?? 0 })
    var borrow = 0
    for index in 0..<a.count {
      var digit = a[index] - borrow - (index < b.count ? b[index] : 0)
      if digit < 0 {
        digit += 10
        borrow = 1
      } else {
        borrow = 0
      }
      result.append(digit)
    }
    while result.count > 1 && result.last == 0 { result.removeLast() }
    return result.reversed().map(String.init).joined()
  }

  private static func multiplyDigits(_ lhs: String, _ rhs: String) -> String {
    if lhs == "0" || rhs == "0" { return "0" }
    let a = Array(lhs.reversed().map { Int(String($0)) ?? 0 })
    let b = Array(rhs.reversed().map { Int(String($0)) ?? 0 })
    var result = Array(repeating: 0, count: a.count + b.count)
    for i in 0..<a.count {
      var carry = 0
      for j in 0..<b.count {
        let total = result[i + j] + a[i] * b[j] + carry
        result[i + j] = total % 10
        carry = total / 10
      }
      var k = i + b.count
      while carry > 0 {
        let total = result[k] + carry
        result[k] = total % 10
        carry = total / 10
        k += 1
      }
    }
    while result.count > 1 && result.last == 0 { result.removeLast() }
    return result.reversed().map(String.init).joined()
  }

  private static func divideDigits(_ lhs: String, _ rhs: String) -> String {
    if compareDigits(lhs, rhs) < 0 { return "0" }
    var remainder = ""
    var quotient = ""
    for digit in lhs {
      remainder.append(digit)
      remainder = String(remainder.drop(while: { $0 == "0" }))
      if remainder.isEmpty { remainder = "0" }
      var count = 0
      while compareDigits(remainder, rhs) >= 0 {
        remainder = subtractDigits(remainder, rhs)
        count += 1
      }
      quotient.append(String(count))
    }
    quotient = String(quotient.drop(while: { $0 == "0" }))
    return quotient.isEmpty ? "0" : quotient
  }

  private static func powerOfTwo(_ exponent: Int) -> String {
    var result = "1"
    for _ in 0..<exponent { result = multiplyDigits(result, "2") }
    return result
  }

  private static func bitLength(_ digits: String) -> Int {
    if digits == "0" { return 1 }
    var value = digits
    var bits = 0
    while value != "0" {
      value = divideDigits(value, "2")
      bits += 1
    }
    return bits
  }

  private static func twosComplement(_ value: String, width: Int) -> String {
    if !value.hasPrefix("-") {
      let binary = toBinary(strip(value))
      return String(repeating: "0", count: max(0, width - binary.count)) + binary
    }
    let magnitude = strip(value)
    let binary = toBinary(magnitude)
    let padded = String(repeating: "0", count: max(0, width - binary.count)) + binary
    let flipped = padded.map { $0 == "0" ? "1" : "0" }
    let incremented = addBinary(flipped.joined(), "1", width: width)
    return String(incremented.suffix(width))
  }

  private static func fromTwosComplement(_ bits: String) -> String {
    if bits.first == "0" {
      let stripped = String(bits.drop(while: { $0 == "0" }))
      return stripped.isEmpty ? "0" : fromBinary(stripped)
    }
    let flipped = bits.map { $0 == "0" ? "1" : "0" }
    let incremented = addBinary(flipped.joined(), "1", width: bits.count)
    let magnitude = fromBinary(String(incremented.suffix(bits.count)))
    return magnitude == "0" ? "0" : "-\(magnitude)"
  }

  private static func toBinary(_ digits: String) -> String {
    if digits == "0" { return "0" }
    var value = digits
    var bits = ""
    while value != "0" {
      let bit = value.last.map { (Int(String($0)) ?? 0) % 2 } ?? 0
      bits.append(String(bit))
      value = divideDigits(value, "2")
    }
    return String(bits.reversed())
  }

  private static func fromBinary(_ bits: String) -> String {
    var result = "0"
    for bit in bits {
      result = multiplyDigits(result, "2")
      if bit == "1" { result = addDigits(result, "1") }
    }
    return result
  }

  private static func addBinary(_ lhs: String, _ rhs: String, width: Int) -> String {
    let a = Array(lhs.reversed())
    let b = Array(rhs.reversed())
    var result: [Character] = []
    var carry = 0
    for index in 0..<max(a.count, b.count) {
      let x = index < a.count && a[index] == "1" ? 1 : 0
      let y = index < b.count && b[index] == "1" ? 1 : 0
      let total = x + y + carry
      result.append(total % 2 == 1 ? "1" : "0")
      carry = total / 2
    }
    while carry > 0 {
      result.append(carry % 2 == 1 ? "1" : "0")
      carry /= 2
    }
    while result.count < width { result.append("0") }
    return String(result.reversed())
  }
}
