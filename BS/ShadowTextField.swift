import AppKit
import SwiftUI

/// NSTextField wrapper that applies NSShadow directly to rendered text
struct ShadowTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = NSFont.systemFont(ofSize: 22, weight: .light)
        if let rounded = NSFont(descriptor: tf.font!.fontDescriptor.withDesign(.rounded)!, size: 22) {
            tf.font = rounded
        }
        tf.textColor = .white
        let placeholderShadow = NSShadow()
        placeholderShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        placeholderShadow.shadowOffset = NSSize(width: 0, height: -0.5)
        placeholderShadow.shadowBlurRadius = 1.5
        tf.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .font: tf.font!,
                .shadow: placeholderShadow,
            ]
        )
        tf.delegate = context.coordinator
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true

        // Text shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        tf.shadow = shadow

        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text.wrappedValue = tf.stringValue
        }
    }
}
