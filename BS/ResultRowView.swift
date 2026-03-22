import SwiftUI
import AppKit

struct ResultRowView: View {
    let result: SearchResult
    let index: Int
    let isSelected: Bool
    let onOpen: () -> Void
    let onCopyImage: () -> Void
    let onShowInFinder: () -> Void
    let showAIBadge: Bool

    @State private var copyFlash = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(result: result)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0.5)
                    .lineLimit(1)

                Text(result.path)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.65))
                    .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0.5)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if showAIBadge {
                matchBadge(source: result.matchSource)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .allowsHitTesting(false) // Let clicks pass through text/icons to the overlay
        .overlay {
            ClickableOverlay(action: onOpen)
        }
        .overlay(alignment: .trailing) {
            if result.isImage {
                CopyButton(copyFlash: $copyFlash, action: {
                    onCopyImage()
                    copyFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        copyFlash = false
                    }
                })
                .padding(.trailing, showAIBadge ? 90 : 20)
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") { onShowInFinder() }
            Divider()
            if result.isImage {
                Button("Copy Image") { onCopyImage() }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.path, forType: .string)
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.name, forType: .string)
            }
        }
    }

    private func matchBadge(source: MatchSource) -> some View {
        let (label, color): (String, Color) = {
            switch source {
            case .exact: return ("", .clear)
            case .fuzzy: return ("~fuzzy", .orange)
            case .semantic: return ("🧠 similar", .purple)
            case .category: return ("📁 category", .blue)
            case .contentMatch: return ("📄 content", .green)
            }
        }()

        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.35))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Transparent clickable overlay — sits on top, catches all clicks

struct ClickableOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickOverlayView {
        let v = ClickOverlayView()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: ClickOverlayView, context: Context) {
        nsView.action = action
    }

    class ClickOverlayView: NSView {
        var action: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            if event.clickCount == 1 {
                action?()
            }
        }
    }
}

// MARK: - AppKit-backed copy button that ALWAYS receives clicks

struct CopyButton: NSViewRepresentable {
    @Binding var copyFlash: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "Copy")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .white.withAlphaComponent(0.7)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
        button.setContentHuggingPriority(.required, for: .horizontal)

        // Set fixed size
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true

        button.toolTip = "Copy image to clipboard"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        if copyFlash {
            nsView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
            nsView.contentTintColor = .systemGreen
        } else {
            nsView.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "Copy")
            nsView.contentTintColor = .white.withAlphaComponent(0.7)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func clicked() {
            action()
        }
    }
}
