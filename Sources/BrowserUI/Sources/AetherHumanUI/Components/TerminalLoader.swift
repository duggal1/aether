import SwiftUI

/// A fixed-width, low-overhead terminal indicator. Never starts a timer per row.
public struct TerminalLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.aetherTheme) private var theme
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: reduced)) { context in
            let index = reduced ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
            Text(Self.frames[index])
                .font(AetherType.mono(14))
                .foregroundStyle(theme.muted)
                .frame(width: 15, height: 17, alignment: .center)
                .accessibilityHidden(true)
        }
        .frame(width: 15, height: 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
