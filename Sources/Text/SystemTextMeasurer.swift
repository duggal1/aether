import EngineCore
import Foundation

#if canImport(CoreText)
  import CoreText
  import CoreGraphics

  public struct SystemTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(_ text: String, fontSize: Double, fontWeight: Int, maxWidth: Double?)
      -> TextRunMetrics
    {
      let weight = CGFloat(floatLiteral: min(1, max(-1, Double(fontWeight - 400) / 500)))
      let descriptor = CTFontDescriptorCreateWithAttributes(
        [
          kCTFontTraitsAttribute: [kCTFontWeightTrait: weight] as CFDictionary
        ] as CFDictionary)
      let font = CTFontCreateWithFontDescriptor(
        descriptor, CGFloat(floatLiteral: fontSize), nil)
      let key = NSAttributedString.Key(kCTFontAttributeName as String)
      let attributed = NSAttributedString(string: text, attributes: [key: font])
      let framesetter = CTFramesetterCreateWithAttributedString(attributed)
      let constrainedWidth: CGFloat =
        maxWidth.map { CGFloat(floatLiteral: $0) } ?? CGFloat.greatestFiniteMagnitude
      let constraint = CGSize(
        width: constrainedWidth,
        height: CGFloat.greatestFiniteMagnitude)
      let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(location: 0, length: attributed.length), nil, constraint, nil)
      let ascent = Double(CTFontGetAscent(font))
      let descent = Double(CTFontGetDescent(font))
      let leading = Double(CTFontGetLeading(font))
      return TextRunMetrics(
        size: Size(width: Double(ceil(suggested.width)), height: Double(ceil(suggested.height))),
        ascent: ascent, descent: descent, leading: leading)
    }
  }
#else
  public struct SystemTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(_ text: String, fontSize: Double, fontWeight: Int, maxWidth: Double?)
      -> TextRunMetrics
    {
      let rawWidth = Double(text.count) * fontSize * 0.56
      let lineHeight = fontSize * 1.2
      if let maxWidth, maxWidth > 0, rawWidth > maxWidth {
        let lines = ceil(rawWidth / maxWidth)
        return TextRunMetrics(
          size: Size(width: maxWidth, height: lineHeight * lines), ascent: fontSize * 0.8,
          descent: fontSize * 0.2)
      }
      return TextRunMetrics(
        size: Size(width: rawWidth, height: lineHeight), ascent: fontSize * 0.8,
        descent: fontSize * 0.2)
    }
  }
#endif
