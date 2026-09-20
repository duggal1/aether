import SwiftUI

public enum AetherBrandMark: String, CaseIterable, Identifiable, Sendable {
    case seat
    case abstract
    case puzzle
    case lightning
    case flow
    case fastForward

    public var id: Self { self }

    public var label: String {
        switch self {
        case .seat: "Seat"
        case .abstract: "Abstract"
        case .puzzle: "Puzzle"
        case .lightning: "Lightning"
        case .flow: "Flow"
        case .fastForward: "Fast forward"
        }
    }

    var viewBox: CGSize {
        switch self {
        case .seat: CGSize(width: 1200, height: 1250)
        case .abstract: CGSize(width: 1300, height: 1301)
        case .puzzle: CGSize(width: 1300, height: 1301)
        case .lightning: CGSize(width: 801, height: 1400)
        case .flow: CGSize(width: 1103, height: 1326)
        case .fastForward: CGSize(width: 1435, height: 814)
        }
    }

    var usesEvenOddFill: Bool { self == .flow || self == .fastForward }

    var svgPathData: String {
        switch self {
        case .seat:
            return """
            M1100 250V505C1083 501.5 1066 500 1049 500C1041 500 1033.5 500.5 1025.5 501C899 513 800.007 626 800.007 758.493V849.993H400.007V758.493C400.007 625.993 301.007 513 174.514 501C149.514 498.5 124.514 500 100.014 505V250C100.014 112 212.014 0 350.014 0H850.014C988.014 0 1100.01 112 1100.01 250H1100Z
            M1200 754.506V1100C1200 1182.5 1132.5 1250 1050 1250H150C67.5 1250 0 1182.5 0 1100V753C0 721 8.5 689 27 663.5C57 622 102 600 150 600C155 600 160 600 165 600.5C240.5 608 300 677 300 758.5V949.993H900V758.5C900 718 915 680 939 652C963.5 623.5 997 604 1035 600.5C1088 595.5 1138.5 618 1171 661C1191 687.5 1200 721.5 1200 754.5V754.506Z
            """

        case .abstract:
            return """
            M1101 253.001L289.001 9.50781C268.001 3.00781 246.501 0.0078125 224.501 0.0078125C100.501 0.0078125 -0.00585938 100.508 -0.00585938 224.514C-0.00585938 246.014 2.99414 268.014 9.49414 288.514L252.987 1101.02C288.987 1220.02 396.481 1300.02 520.481 1300.02C674.481 1300.02 799.974 1174.52 799.974 1020.53V950.028C799.974 867.528 867.474 800.028 949.974 800.028H1020.47C1174.47 800.028 1299.97 674.528 1299.97 520.534C1299.97 396.534 1219.97 289.041 1100.97 253.041L1101 253.001Z
            """

        case .puzzle:
            return """
            M1200 900C1114.5 900 1045.49 828.5 1050 742C1054 661 1127 600 1208 600H1300V400C1300 289.5 1210.5 200 1100 200H950C950 89.5 860.5 0 750 0C639.5 0 550 89.5 550 200H400C289.5 200 200 289.5 200 400V550C89.5 550 0 639.5 0 750C0 860.5 89.5 950 200 950V1100C200 1210.5 289.5 1300 400 1300H600V1208.5C600 1127.5 661 1054.5 742 1050.5C828.5 1046 900 1115 900 1200.5V1300.5H1100C1210.5 1300.5 1300 1211 1300 1100.5V900.5L1200 900Z
            """

        case .lightning:
            return """
            M642.507 450H566.507L645.007 175.493C648.007 162.993 650.007 150.493 650.007 137.493C650.007 61.9933 588.007 0 512.514 0H293.021C215.021 0 148.021 50 125.527 124.5L6.02734 523.5C2.02734 536 0.0273438 549.5 0.0273438 563C0.0273438 638.5 61.5273 700 137.027 700H188.027L51.0273 1339.49C46.5273 1361.49 57.0273 1383.99 77.0273 1394.49C84.0273 1397.99 92.0273 1399.99 100.027 1399.99C113.527 1399.99 127.027 1394.49 136.527 1383.99L758.021 714.993C785.021 685.993 800.021 647.493 800.021 607.493C800.021 520.993 729.021 450 642.527 450H642.507Z
            """

        case .flow:
            return """
            M751.372 962.569C777.899 962.569 803.345 952.043 822.096 933.293C840.847 914.543 851.372 889.096 851.372 862.569V637.569C851.372 624.319 856.648 611.596 866.023 602.22C875.397 592.844 888.121 587.569 901.372 587.569H1001.37C1014.65 587.569 1027.37 592.845 1036.75 602.22C1046.12 611.594 1051.37 624.318 1051.37 637.569V912.569C1051.37 978.872 1025.05 1042.47 978.148 1089.34C931.273 1136.24 867.7 1162.57 801.375 1162.57H476.375V1225.17C476.375 1261.01 457.177 1294.14 426.025 1311.97C394.9 1329.77 356.599 1329.54 325.676 1311.34C247.649 1265.44 126.556 1194.22 49.3027 1148.77C18.7507 1130.8 0 1098.02 0 1062.57C0 1027.15 18.7493 994.348 49.3027 976.395C126.553 930.947 247.649 859.697 325.676 813.795C356.603 795.617 394.9 795.393 426.025 813.196C457.176 830.998 476.375 864.122 476.375 899.998V962.572L751.372 962.569Z
            M626.372 162.569V99.9956C626.372 64.1209 645.596 30.9956 676.721 13.1929C707.872 -4.60975 746.169 -4.38042 777.071 13.7919C855.123 59.6932 976.217 130.943 1053.47 176.392C1084.02 194.34 1102.77 227.141 1102.77 262.569C1102.77 298.017 1084.02 330.793 1053.47 348.767C976.22 394.215 855.124 465.444 777.071 511.34C746.169 529.537 707.873 529.767 676.721 511.965C645.596 494.142 626.372 461.017 626.372 425.162V362.564H351.372C324.872 362.564 299.424 373.116 280.675 391.866C261.925 410.617 251.372 436.044 251.372 462.564V687.564C251.372 700.84 246.122 713.537 236.747 722.938C227.372 732.313 214.648 737.564 201.372 737.564H101.372C73.7733 737.564 51.372 715.189 51.372 687.564V412.564C51.372 346.261 77.7213 282.689 124.596 235.79C171.497 188.916 235.069 162.566 301.369 162.566L626.372 162.569Z
            """

        case .fastForward:
            return """
            M615.329 323.381C505.017 249.845 275.876 97.0743 155.489 16.781C124.801 -3.66702 85.3493 -5.55766 52.828 11.8226C20.3067 29.2293 0 63.1199 0 100.016V713.136C0 750.032 20.312 783.923 52.828 801.329C85.3493 818.704 124.797 816.819 155.489 796.371C275.88 716.084 505.023 563.318 615.329 489.771C643.168 471.244 659.881 440.011 659.881 406.573C659.881 373.136 643.173 341.902 615.329 323.376V323.381Z
            M1390.37 323.381C1280.06 249.845 1050.92 97.0743 930.529 16.781C899.841 -3.66702 860.389 -5.55766 827.868 11.8226C795.346 29.2293 775.04 63.1199 775.04 100.016V713.136C775.04 750.032 795.352 783.923 827.868 801.329C860.389 818.704 899.837 816.819 930.529 796.371C1050.92 716.084 1280.06 563.318 1390.37 489.771C1418.21 471.244 1434.92 440.011 1434.92 406.573C1434.92 373.136 1418.21 341.902 1390.37 323.376V323.381Z
            """
        }
    }
}

public struct AetherBrandMarkShape: Shape {
    let mark: AetherBrandMark

    public init(_ mark: AetherBrandMark) { self.mark = mark }

    public func path(in rect: CGRect) -> Path {
        let viewBox = mark.viewBox
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let x = rect.midX - viewBox.width * scale / 2
        let y = rect.midY - viewBox.height * scale / 2
        return SVGPathParser.parse(mark.svgPathData).applying(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y)
        )
    }
}

public struct AetherBrandMarkView: View {
    public let mark: AetherBrandMark
    public var tint: Color?
    public init(_ mark: AetherBrandMark, tint: Color? = nil) {
        self.mark = mark
        self.tint = tint
    }
    public var body: some View {
        AetherBrandMarkShape(mark)
            .fill(tint ?? Color.primary, style: FillStyle(eoFill: mark.usesEvenOddFill))
            .accessibilityLabel(Text(mark.label))
    }
}

private enum SVGPathParser {
private static let tokenPattern = try! NSRegularExpression(
    pattern: #"[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#
)

static func parse(_ data: String) -> Path {
    let range = NSRange(data.startIndex..<data.endIndex, in: data)
    let tokens = tokenPattern.matches(in: data, range: range).compactMap {
        Range($0.range, in: data).map { String(data[$0]) }
    }
    var p = Path()
    var position = CGPoint.zero
    var beginning = CGPoint.zero
    var index = 0
    var command: Character?
    var previous: Character?
    var lastCubic: CGPoint?
    var lastQuadratic: CGPoint?

    func number() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]) else {
            assertionFailure("Malformed SVG path")
            return 0
        }
        index += 1
        return CGFloat(value)
    }
    func point(_ relative: Bool) -> CGPoint {
        let xy = CGPoint(x: number(), y: number())
        return relative ? CGPoint(x: position.x + xy.x, y: position.y + xy.y) : xy
    }
    func reflected(_ last: CGPoint?) -> CGPoint {
        guard let last else { return position }
        return CGPoint(x: 2 * position.x - last.x, y: 2 * position.y - last.y)
    }

    while index < tokens.count {
        if tokens[index].count == 1, let token = tokens[index].first,
           token.isLetter {
            command = token
            index += 1
        }
        guard let cmd = command else { break }
        let relative = cmd.isLowercase
        let upper = Character(cmd.uppercased())

        switch upper {
        case "M":
            position = point(relative)
            beginning = position
            p.move(to: position)
            command = relative ? "l" : "L"
            lastCubic = nil; lastQuadratic = nil
        case "L":
            position = point(relative)
            p.addLine(to: position)
            lastCubic = nil; lastQuadratic = nil
        case "H":
            let x = number()
            position.x = relative ? position.x + x : x
            p.addLine(to: position)
            lastCubic = nil; lastQuadratic = nil
        case "V":
            let y = number()
            position.y = relative ? position.y + y : y
            p.addLine(to: position)
            lastCubic = nil; lastQuadratic = nil
        case "C":
            let c1 = point(relative)
            let c2 = point(relative)
            position = point(relative)
            p.addCurve(to: position, control1: c1, control2: c2)
            lastCubic = c2; lastQuadratic = nil
        case "S":
            let c1 = previous == "C" || previous == "S" ? reflected(lastCubic) : position
            let c2 = point(relative)
            position = point(relative)
            p.addCurve(to: position, control1: c1, control2: c2)
            lastCubic = c2; lastQuadratic = nil
        case "Q":
            let c = point(relative)
            position = point(relative)
            p.addQuadCurve(to: position, control: c)
            lastQuadratic = c; lastCubic = nil
        case "T":
            let c = previous == "Q" || previous == "T" ? reflected(lastQuadratic) : position
            position = point(relative)
            p.addQuadCurve(to: position, control: c)
            lastQuadratic = c; lastCubic = nil
        case "A":
            let rx = number(), ry = number(), degrees = number()
            let large = number() != 0, sweep = number() != 0
            let target = point(relative)
            appendSVGArc(to: &p, from: position, to: target,
                         rx: rx, ry: ry, degrees: degrees, large: large, sweep: sweep)
            position = target
            lastCubic = nil; lastQuadratic = nil
        case "Z":
            p.closeSubpath()
            position = beginning
            command = nil
            lastCubic = nil; lastQuadratic = nil
        default:
            assertionFailure("Unsupported SVG command: \(cmd)")
            return p
        }
        previous = upper
    }
    return p
}

/// W3C endpoint-to-center arc conversion. Each arc section <= 90 degrees
/// becomes a cubic Bézier, so CGPath renders it without an SVG library.
private static func appendSVGArc(
    to path: inout Path, from a: CGPoint, to b: CGPoint,
    rx initialRX: CGFloat, ry initialRY: CGFloat,
    degrees: CGFloat, large: Bool, sweep: Bool
) {
    guard a != b, initialRX != 0, initialRY != 0 else {
        path.addLine(to: b)
        return
    }
    let phi = Double(degrees) * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = Double(a.x - b.x) / 2, dy = Double(a.y - b.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    var rx = abs(Double(initialRX)), ry = abs(Double(initialRY))
    let radiusScale = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if radiusScale > 1 {
        let factor = sqrt(radiusScale)
        rx *= factor; ry *= factor
    }
    let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let coefficient = (large == sweep ? -1.0 : 1.0) * sqrt(numerator / max(denominator, 1e-12))
    let cxLocal = coefficient * rx * y1 / ry
    let cyLocal = coefficient * -ry * x1 / rx
    let centerX = cosPhi * cxLocal - sinPhi * cyLocal + Double(a.x + b.x) / 2
    let centerY = sinPhi * cxLocal + cosPhi * cyLocal + Double(a.y + b.y) / 2

    func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let ux = (x1 - cxLocal) / rx, uy = (y1 - cyLocal) / ry
    let vx = (-x1 - cxLocal) / rx, vy = (-y1 - cyLocal) / ry
    let start = atan2(uy, ux)
    var delta = angle(ux, uy, vx, vy)
    if !sweep && delta > 0 { delta -= 2 * .pi }
    if sweep && delta < 0 { delta += 2 * .pi }
    let pieces = max(1, Int(ceil(abs(delta) / (.pi / 2))))
    let step = delta / Double(pieces)

    func transformed(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: centerX + cosPhi * rx * x - sinPhi * ry * y,
                y: centerY + sinPhi * rx * x + cosPhi * ry * y)
    }
    for section in 0..<pieces {
        let t0 = start + Double(section) * step
        let t1 = t0 + step
        let tangent = 4 / 3 * tan(step / 4)
        let c0 = transformed(cos(t0) - tangent * sin(t0), sin(t0) + tangent * cos(t0))
        let c1 = transformed(cos(t1) + tangent * sin(t1), sin(t1) - tangent * cos(t1))
        let end = section == pieces - 1 ? b : transformed(cos(t1), sin(t1))
        path.addCurve(to: end, control1: c0, control2: c1)
    }
}
}
