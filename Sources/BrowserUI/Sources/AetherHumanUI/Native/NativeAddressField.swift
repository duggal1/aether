import AppKit
import SwiftUI

struct NativeAddressField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let fullAddress: String
    let placeholder: String
    let focusRequest: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onMove: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func addressFont() -> NSFont {
        if let name = AetherFontRegistry.faceName(for: .regular), let font = NSFont(name: name, size: 13) {
            return font
        }
        return .systemFont(ofSize: 13)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = AddressTextField()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = addressFont()
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Address and search")
        field.setAccessibilityIdentifier("aether.address")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeAddressField
        var lastFocusRequest: Int
        init(_ parent: NativeAddressField) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let full = parent.fullAddress
            DispatchQueue.main.async { [weak field] in
                self.parent.focused = true
                guard let field, !full.isEmpty else { return }
                field.stringValue = full
                self.parent.text = full
                field.currentEditor()?.selectAll(nil)
            }
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            DispatchQueue.main.async { self.parent.text = value }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async { self.parent.focused = false }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                control.window?.makeFirstResponder(nil)
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                control.window?.makeFirstResponder(nil)
                return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                parent.onMove(-1)
                return true
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                parent.onMove(1)
                return true
            }
            return false
        }
    }
}

private final class AddressTextField: NSTextField {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 20) }
}
