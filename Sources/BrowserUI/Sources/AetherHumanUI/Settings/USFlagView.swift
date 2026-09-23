import SwiftUI

// Compact US flag for the Search Location country row.
// Geometry and colors taken exactly from the supplied 22x16 flag asset:
// white field, #0831FF canton, #FF0F1B stripes, white star blocks.
struct USFlagView: View {
    private static let blue = Color(red: 0x08 / 255, green: 0x31 / 255, blue: 0xFF / 255)
    private static let red = Color(red: 0xFF / 255, green: 0x0F / 255, blue: 0x1B / 255)

    private static let stars: [CGRect] = [
        CGRect(x: 1.04688, y: 1.06665, width: 1.04761, height: 1.06667),
        CGRect(x: 3.14211, y: 1.06665, width: 1.04762, height: 1.06667),
        CGRect(x: 5.23735, y: 1.06665, width: 1.04762, height: 1.06667),
        CGRect(x: 7.33259, y: 1.06665, width: 1.04762, height: 1.06667),
        CGRect(x: 6.28497, y: 2.13332, width: 1.04762, height: 1.06666),
        CGRect(x: 4.18973, y: 2.13332, width: 1.04762, height: 1.06666),
        CGRect(x: 2.09449, y: 2.13332, width: 1.04762, height: 1.06666),
        CGRect(x: 1.04688, y: 3.19998, width: 1.04761, height: 1.06667),
        CGRect(x: 3.14211, y: 3.19998, width: 1.04762, height: 1.06667),
        CGRect(x: 5.23735, y: 3.19998, width: 1.04762, height: 1.06667),
        CGRect(x: 7.33259, y: 3.19998, width: 1.04762, height: 1.06667),
        CGRect(x: 6.28497, y: 4.26665, width: 1.04762, height: 1.06667),
        CGRect(x: 4.18973, y: 4.26665, width: 1.04762, height: 1.06667),
        CGRect(x: 2.09449, y: 4.26665, width: 1.04762, height: 1.06667),
        CGRect(x: 1.04688, y: 5.33332, width: 1.04761, height: 1.06666),
        CGRect(x: 3.14211, y: 5.33332, width: 1.04762, height: 1.06666),
        CGRect(x: 5.23735, y: 5.33332, width: 1.04762, height: 1.06666),
        CGRect(x: 7.33259, y: 5.33332, width: 1.04762, height: 1.06666),
    ]

    var body: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / 22
            let sy = proxy.size.height / 16
            ZStack(alignment: .topLeading) {
                Color.white
                Self.blue.frame(width: 9.42857 * sx, height: 7.46667 * sy)
                Stripes(sx: sx, sy: sy)
                ForEach(Self.stars.indices, id: \.self) { index in
                    let star = Self.stars[index]
                    Color.white.frame(width: star.width * sx, height: star.height * sy)
                        .offset(x: star.minX * sx, y: star.minY * sy)
                }
            }
        }
        .frame(width: 18, height: 13)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .accessibilityHidden(true)
    }

    private struct Stripes: View {
        let sx: CGFloat
        let sy: CGFloat
        var body: some View {
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { row in
                    USFlagView.red
                        .frame(width: (22 - 9.42857) * sx, height: 1.06667 * sy)
                        .offset(x: 9.42857 * sx, y: Double(row * 2) * 1.06667 * sy)
                }
                ForEach(0..<4, id: \.self) { row in
                    USFlagView.red
                        .frame(width: 22 * sx, height: 1.06667 * sy)
                        .offset(y: (8.53333 + Double(row * 2) * 1.06667) * sy)
                }
            }
        }
    }
}
