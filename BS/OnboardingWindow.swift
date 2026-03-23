import AppKit
import SwiftUI

class OnboardingWindow: NSWindow {

    private var onComplete: (() -> Void)?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Welcome to BetterSearch"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.center()
        self.isReleasedWhenClosed = false
        self.level = .floating

        let view = OnboardingView(
            onComplete: {
                onComplete()
                self.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }
}

// MARK: - Onboarding SwiftUI View

struct OnboardingView: View {
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.purple)
                }

                Text("BetterSearch")
                    .font(.system(size: 28, weight: .bold))

                Text("Lightning-fast file search for macOS")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 32)

            // Features
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "keyboard",
                    title: "⌘ + Shift + Space",
                    description: "Opens search instantly from anywhere on your desktop"
                )

                featureRow(
                    icon: "bolt.fill",
                    title: "AI-Powered Search",
                    description: "Fuzzy match, semantic search, category detection — finds what you mean, not just what you type"
                )

                featureRow(
                    icon: "doc.on.doc.fill",
                    title: "Copy & Drag",
                    description: "Copy images to clipboard, drag files into any app, right-click for path"
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Spacer()

            // Start button
            VStack(spacing: 8) {
                Button(action: onComplete) {
                    Text("Start Searching")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)

                Text("BetterSearch runs in the menu bar · Press ⌘⇧Space anytime")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 400)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
