
import SwiftUI

// MARK: - Aether Logo

public struct AetherLogo: View {

    @Environment(\.colorScheme)
    private var colorScheme
    private let tint: Color?

    public init(tint: Color? = nil) { self.tint = tint }

    public var body: some View {
        AetherLogoShape()
            .fill(
                tint ?? (colorScheme == .dark
                    ? Color(
                        red: 245 / 255,
                        green: 245 / 255,
                        blue: 244 / 255
                    )
                    : Color(
                        red: 28 / 255,
                        green: 25 / 255,
                        blue: 23 / 255
                    ))
            )
            .aspectRatio(
                142 / 109,
                contentMode: .fit
            )
            .accessibilityLabel("Aether")
    }

}

// MARK: - Vector Shape

private struct AetherLogoShape: Shape {

    func path(in rect: CGRect) -> Path {

        var path = Path()

        path.move(to: CGPoint(x: 0.97, y: 59.22))

        path.addLine(
            to: CGPoint(x: 0.01, y: 102.38)
        )

        path.addQuadCurve(
            to: CGPoint(x: 0.28, y: 103.55),
            control: CGPoint(x: 0, y: 103)
        )

        path.addLine(
            to: CGPoint(x: 2.31, y: 107.62)
        )

        path.addQuadCurve(
            to: CGPoint(x: 4.55, y: 109),
            control: CGPoint(x: 3, y: 109)
        )

        path.addLine(
            to: CGPoint(x: 47.51, y: 109)
        )

        path.addQuadCurve(
            to: CGPoint(x: 49.71, y: 107.69),
            control: CGPoint(x: 49, y: 109)
        )

        path.addLine(
            to: CGPoint(x: 75.77, y: 59.42)
        )

        path.addQuadCurve(
            to: CGPoint(x: 76.37, y: 58.69),
            control: CGPoint(x: 76, y: 59)
        )

        path.addLine(
            to: CGPoint(x: 81.02, y: 54.81)
        )

        path.addQuadCurve(
            to: CGPoint(x: 83.23, y: 54.31),
            control: CGPoint(x: 82, y: 54)
        )

        path.addLine(
            to: CGPoint(x: 85.06, y: 54.77)
        )

        path.addQuadCurve(
            to: CGPoint(x: 86.54, y: 55.8),
            control: CGPoint(x: 86, y: 55)
        )

        path.addLine(
            to: CGPoint(x: 89.58, y: 60.37)
        )

        path.addQuadCurve(
            to: CGPoint(x: 90, y: 61.76),
            control: CGPoint(x: 90, y: 61)
        )

        path.addLine(
            to: CGPoint(x: 90, y: 105.96)
        )

        path.addQuadCurve(
            to: CGPoint(x: 90.73, y: 107.73),
            control: CGPoint(x: 90, y: 107)
        )

        path.addLine(
            to: CGPoint(x: 91.27, y: 108.27)
        )

        path.addQuadCurve(
            to: CGPoint(x: 93.04, y: 109),
            control: CGPoint(x: 92, y: 109)
        )

        path.addLine(
            to: CGPoint(x: 138.66, y: 109)
        )

        path.addQuadCurve(
            to: CGPoint(x: 140.74, y: 107.89),
            control: CGPoint(x: 140, y: 109)
        )

        path.addLine(
            to: CGPoint(x: 141.56, y: 106.65)
        )

        path.addQuadCurve(
            to: CGPoint(x: 141.98, y: 105.22),
            control: CGPoint(x: 142, y: 106)
        )

        path.addLine(
            to: CGPoint(x: 141.03, y: 58.31)
        )

        path.addQuadCurve(
            to: CGPoint(x: 139.91, y: 56.28),
            control: CGPoint(x: 141, y: 57)
        )

        path.addLine(
            to: CGPoint(x: 138.63, y: 55.42)
        )

        path.addQuadCurve(
            to: CGPoint(x: 137.24, y: 55),
            control: CGPoint(x: 138, y: 55)
        )

        path.addLine(
            to: CGPoint(x: 94.04, y: 55)
        )

        path.addQuadCurve(
            to: CGPoint(x: 92.27, y: 54.27),
            control: CGPoint(x: 93, y: 55)
        )

        path.addLine(
            to: CGPoint(x: 90.71, y: 52.71)
        )

        path.addQuadCurve(
            to: CGPoint(x: 89.98, y: 51),
            control: CGPoint(x: 90, y: 52)
        )

        path.addLine(
            to: CGPoint(x: 89.02, y: 5)
        )

        path.addQuadCurve(
            to: CGPoint(x: 88.29, y: 3.29),
            control: CGPoint(x: 89, y: 4)
        )

        path.addLine(
            to: CGPoint(x: 85.76, y: 0.76)
        )

        path.addQuadCurve(
            to: CGPoint(x: 83.93, y: 0.03),
            control: CGPoint(x: 85, y: 0)
        )

        path.addLine(
            to: CGPoint(x: 47.45, y: 0.96)
        )

        path.addQuadCurve(
            to: CGPoint(x: 45.31, y: 2.27),
            control: CGPoint(x: 46, y: 1)
        )

        path.addLine(
            to: CGPoint(x: 19.17, y: 50.68)
        )

        path.addQuadCurve(
            to: CGPoint(x: 18.74, y: 51.26),
            control: CGPoint(x: 19, y: 51)
        )

        path.addLine(
            to: CGPoint(x: 15.73, y: 54.27)
        )

        path.addQuadCurve(
            to: CGPoint(x: 13.96, y: 55),
            control: CGPoint(x: 15, y: 55)
        )

        path.addLine(
            to: CGPoint(x: 5.83, y: 55)
        )

        path.addQuadCurve(
            to: CGPoint(x: 4.33, y: 55.5),
            control: CGPoint(x: 5, y: 55)
        )

        path.addLine(
            to: CGPoint(x: 1.97, y: 57.27)
        )

        path.addQuadCurve(
            to: CGPoint(x: 0.97, y: 59.22),
            control: CGPoint(x: 1, y: 58)
        )

        path.closeSubpath()

        // Scale the original 142 × 109 vector
        // into the available SwiftUI bounds.

        let transform = CGAffineTransform(
            translationX: rect.minX,
            y: rect.minY
        )
        .scaledBy(
            x: rect.width / 142,
            y: rect.height / 109
        )

        return path.applying(transform)
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    AetherLogo()
        .frame(width: 142)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(
            red: 250 / 255,
            green: 250 / 255,
            blue: 249 / 255
        ))
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    AetherLogo()
        .frame(width: 142)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(
            red: 28 / 255,
            green: 25 / 255,
            blue: 23 / 255
        ))
        .preferredColorScheme(.dark)
}
