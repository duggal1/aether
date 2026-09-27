import EngineRuntime
import SwiftUI

struct AgentCursorOverlay: View {
    let update: AgentInteractionUpdate
    @State private var darkSurface = false
    @State private var point: CGPoint = .zero
    @State private var shownKind: AgentInteractionKind
    @State private var displayedSequence: UInt64

    init(update: AgentInteractionUpdate) {
        self.update = update
        _point = State(initialValue: CGPoint(x: update.point?.x ?? 0, y: update.point?.y ?? 0))
        _shownKind = State(initialValue: update.kind)
        _displayedSequence = State(initialValue: update.sequence)
    }

    var body: some View {
        GeometryReader { geometry in
            if let target = update.point {
                let scaleX = geometry.size.width / CGFloat(max(1, update.viewport?.width ?? Double(geometry.size.width)))
                let scaleY = geometry.size.height / CGFloat(max(1, update.viewport?.height ?? Double(geometry.size.height)))
                cursor
                    .position(x: point.x * scaleX + 9, y: point.y * scaleY + 9)
                    .onAppear {
                        point = CGPoint(x: target.x, y: target.y)
                        if let luminance = update.targetLuminance { darkSurface = luminance > 0.5 }
                    }
                    .onChange(of: target) { _, next in
                        if let luminance = update.targetLuminance {
                            if luminance > 0.56 { darkSurface = true }
                            if luminance < 0.44 { darkSurface = false }
                        }
                        withAnimation(.linear(duration: max(0.001, update.movementDuration))) {
                            point = CGPoint(x: next.x, y: next.y)
                        }
                    }
                    .onChange(of: update.sequence) { _, sequence in
                        displayedSequence = sequence
                        shownKind = update.kind
                        guard update.kind == .click else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(120))
                            guard displayedSequence == sequence else { return }
                            shownKind = .move
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var cursor: some View {
        let path = SVGCursorShape(data: Self.path(for: shownKind))
        ZStack {
            path.stroke(LinearGradient(gradient: Gradient(colors: Self.violet),
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.1)
                .blur(radius: 1.1)
                .opacity(0.32)
            path.stroke(LinearGradient(gradient: Gradient(colors: Self.violet),
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.0)
            path.stroke(darkSurface ? Color.white : Color.black,
                style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.08), value: shownKind)
        .onChange(of: update.targetLuminance) { _, luminance in
            guard let luminance else { return }
            if luminance > 0.56 { darkSurface = true }
            if luminance < 0.44 { darkSurface = false }
        }
    }

    private static let violet: [Color] = [
        Color(red: 0.31, green: 0.04, blue: 0.96),
        Color(red: 0.66, green: 0.08, blue: 1.0),
        Color(red: 0.39, green: 0.12, blue: 1.0),
    ]

    private static func path(for kind: AgentInteractionKind) -> String {
        switch kind {
        case .click:
            return "M10.4654 19.0065L8.02099 11.9843L8.02098 11.9843C7.10172 9.34346 6.64208 8.02305 7.33296 7.3327C8.02385 6.64236 9.3453 7.10164 11.9882 8.02019L19.0012 10.4576C20.4673 10.9671 21.2003 11.2219 21.3585 11.7154C21.4021 11.8514 21.4172 11.9949 21.4027 12.1371C21.3503 12.6526 20.686 13.0536 19.3574 13.8556C18.5055 14.3698 18.0796 14.6269 17.966 15.0149C17.9339 15.1247 17.9201 15.2391 17.9253 15.3534C17.9436 15.7572 18.2964 16.1078 19.002 16.8091L21.3211 19.114L21.3211 19.114C21.6683 19.4591 21.8419 19.6316 21.9216 19.8246C22.0258 20.0772 22.0262 20.3606 21.9226 20.6134C21.8435 20.8066 21.6704 20.9796 21.3241 21.3256C20.9787 21.6708 20.806 21.8434 20.613 21.9224C20.3605 22.0259 20.0774 22.0259 19.8249 21.9224C19.6319 21.8434 19.4592 21.6708 19.1137 21.3256L19.1137 21.3256L16.786 18.9997C16.092 18.3062 15.7449 17.9595 15.3467 17.9387C15.2261 17.9324 15.1054 17.9471 14.99 17.9822C14.6084 18.0982 14.3552 18.5183 13.8487 19.3584L13.8487 19.3584C13.0566 20.6721 12.6606 21.329 12.1522 21.3868C12.0023 21.4038 11.8505 21.388 11.7073 21.3405C11.2217 21.1793 10.9696 20.455 10.4654 19.0065Z M9 4V2M5 5L3.5 3.5M4 9H2M5 13L3.5 14.5M14.5 3.5L13 5"
        case .pointer:
            return "M11.4929 9V11.4211M11.4929 9V4C11.4929 3.17157 10.8213 2.5 9.99289 2.5C9.16446 2.5 8.49289 3.17157 8.49289 4V14L6.18518 11.8369C5.38668 11.238 4.24541 11.4616 3.73188 12.3174C3.40149 12.8681 3.41319 13.5587 3.76205 14.0979L6.32173 18.0095C7.39715 19.6529 7.93486 20.4746 8.74311 20.9492C8.82434 20.9969 8.90722 21.0417 8.99161 21.0836C9.83135 21.5 10.8133 21.5 12.7773 21.5H13.4925C16.3015 21.5 17.7059 21.5 18.7148 20.8259C19.1517 20.534 19.5267 20.1589 19.8186 19.7221C20.4926 18.7131 20.4925 17.3087 20.4924 14.4997L20.4923 13.6755C20.4923 13.0472 20.4923 12.733 20.4223 12.4754C20.2362 11.7908 19.7013 11.256 19.0167 11.07C18.7592 11 18.445 11 17.8166 11M11.4929 9C12.4245 9 12.8904 9 13.2578 9.15218C13.7479 9.35512 14.1372 9.7444 14.3403 10.2344C14.4925 10.6019 14.4926 11.0677 14.4928 11.9993L14.4929 12.3546M17.4929 13L17.4928 12.7667C17.4927 12.053 17.4927 11.6962 17.4026 11.4063C17.2071 10.7776 16.7148 10.2854 16.0861 10.0901C15.7962 10 15.4394 10 14.7257 10"
        case .dragging:
            return "M17.5 9.5V8.75C17.5 7.7835 18.2835 7 19.25 7C20.2165 7 21 7.7835 21 8.75V12.8C21 16.7765 17.7765 20 13.8 20H10.0588C6.16034 20 3 16.8397 3 12.9412V12C3 10.8954 3.89543 10 5 10C6.10457 10 7 10.8954 7 12V12.9412M17.5 9.5V6.75C17.5 5.7835 16.7165 5 15.75 5C14.7835 5 14 5.7835 14 6.75V8.5M14 8.5V5.75C14 4.7835 13.2165 4 12.25 4C11.2835 4 10.5 4.7835 10.5 5.75V8M10.5 8V6.75C10.5 5.7835 9.7165 5 8.75 5C7.7835 5 7 5.7835 7 6.75V12"
        default:
            return "M9.80282 4.62973L15.8364 6.99069C19.3164 8.35243 21.0564 9.03329 20.9987 10.1133C20.941 11.1934 19.1251 11.6886 15.4933 12.6791C14.412 12.974 13.8713 13.1215 13.4964 13.4963C13.1215 13.8712 12.9741 14.4119 12.6791 15.4933C11.6887 19.125 11.1934 20.9409 10.1134 20.9986C9.03335 21.0563 8.35249 19.3163 6.99075 15.8363L4.62979 9.80276C3.20411 6.15934 2.49127 4.33764 3.41448 3.41442C4.3377 2.49121 6.15941 3.20405 9.80282 4.62973Z"
        }
    }
}

private struct SVGCursorShape: Shape {
    let data: String

    func path(in rect: CGRect) -> Path {
        let pattern = #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return Path() }
        let range = NSRange(data.startIndex..., in: data)
        let values = expression.matches(in: data, range: range).compactMap {
            Range($0.range, in: data).map { String(data[$0]) }
        }
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        func number() -> CGFloat {
            defer { index += 1 }
            return index < values.count ? CGFloat(Double(values[index]) ?? 0) : 0
        }
        while index < values.count {
            if values[index].first?.isLetter == true {
                command = values[index].first ?? "M"
                index += 1
                if command == "Z" || command == "z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M", "m", "L", "l":
                let relative = command.isLowercase
                let x = number(), y = number()
                let next = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                if command == "M" || command == "m" { path.move(to: next); command = relative ? "l" : "L" }
                else { path.addLine(to: next) }
                current = next
            case "C", "c":
                let relative = command.isLowercase
                let a = CGPoint(x: number(), y: number())
                let b = CGPoint(x: number(), y: number())
                let end = CGPoint(x: number(), y: number())
                let offset = relative ? current : .zero
                let p1 = CGPoint(x: a.x + offset.x, y: a.y + offset.y)
                let p2 = CGPoint(x: b.x + offset.x, y: b.y + offset.y)
                let p3 = CGPoint(x: end.x + offset.x, y: end.y + offset.y)
                path.addCurve(to: p3, control1: p1, control2: p2)
                current = p3
            default:
                index = values.count
            }
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
