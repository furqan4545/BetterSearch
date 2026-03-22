import AppKit
import SwiftUI

class OnboardingWindow: NSWindow {

    private var onComplete: (() -> Void)?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Welcome to BS"
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

// MARK: - Accessibility Permission Helper

struct AccessibilityHelper {
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Onboarding SwiftUI View

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var hasAccessibility = AccessibilityHelper.hasPermission
    @State private var checkTimer: Timer?
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.purple)

                Text("Better Search")
                    .font(.system(size: 28, weight: .bold))

                Text("Lightning-fast file search for macOS")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 32)

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                stepRow(
                    number: 1,
                    icon: "keyboard",
                    title: "Press ⌘ + Shift + Space",
                    description: "Opens the search bar instantly from anywhere on your desktop",
                    done: true
                )

                stepRow(
                    number: 2,
                    icon: "bolt.fill",
                    title: "Type to search",
                    description: "Finds files, apps, documents — AI-powered fuzzy & semantic search",
                    done: true
                )

                stepRow(
                    number: 3,
                    icon: "hand.raised.fill",
                    title: "Grant Accessibility Permission",
                    description: hasAccessibility
                        ? "Permission granted — global hotkey is active!"
                        : "Required so the hotkey works from any app",
                    done: hasAccessibility
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Spacer()

            // Action button
            VStack(spacing: 12) {
                if hasAccessibility {
                    Button(action: onComplete) {
                        Text("Start Searching")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.large)
                } else {
                    Button(action: {
                        AccessibilityHelper.requestPermission()
                        startPollingPermission()
                    }) {
                        Text("Grant Accessibility Permission")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.large)

                    Text("You can also enable it in System Settings → Privacy & Security → Accessibility")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            if !hasAccessibility {
                startPollingPermission()
            }
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func stepRow(number: Int, icon: String, title: String, description: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                    .frame(width: 36, height: 36)

                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(done ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startPollingPermission() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let granted = AccessibilityHelper.hasPermission
            if granted != hasAccessibility {
                hasAccessibility = granted
                if granted {
                    checkTimer?.invalidate()
                }
            }
        }
    }
}
