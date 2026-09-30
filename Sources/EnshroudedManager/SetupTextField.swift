import AppKit
import SwiftUI

/// Use AppKit's field editor, as in the Valheim manager. SwiftUI updates must
/// never replace an active editor's text or move its selection/first responder.
struct SetupTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var secure = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        field.placeholderString = title
        field.setAccessibilityLabel(title)
        field.stringValue = text
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.currentEditor() == nil && field.stringValue != text { field.stringValue = text }
        field.isEnabled = context.environment.isEnabled
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
