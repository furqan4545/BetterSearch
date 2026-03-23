import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onDismiss: () -> Void = {}

    @State private var selectedIndex: Int? = nil
    @State private var permissionError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if viewModel.isSearching && viewModel.results.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Searching...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }

            if !viewModel.results.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result: result, index: index)
                            if index < viewModel.results.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.25))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 20)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            if !viewModel.isSearching && viewModel.results.isEmpty && viewModel.searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                Text("No results found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }

            // Search speed indicator
            if !viewModel.results.isEmpty && viewModel.searchTimeMs > 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                HStack {
                    Text("\(viewModel.results.count) results in \(String(format: "%.1f", viewModel.searchTimeMs))ms")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.4))
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                    if FileIndexer.shared.ready {
                        Text("⚡ indexed")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.green)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            }
        }
        .frame(width: 680)
        .modifier(KeyPressHandler(
            onUp: { moveSelection(by: -1) },
            onDown: { moveSelection(by: 1) },
            onReturn: { openSelected() }
        ))
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            ShadowTextField(text: $viewModel.searchText, placeholder: "Search files...")
                .frame(height: 30)

            // AI Label
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("AI")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.purple, .purple.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            )
            .foregroundStyle(.white)
            .shadow(color: .purple.opacity(0.5), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func resultRow(result: SearchResult, index: Int) -> some View {
        ResultRowView(
            result: result,
            index: index,
            isSelected: selectedIndex == index,
            isImageSelected: viewModel.selectedImagePaths.contains(result.path),
            onOpen: { safeOpen(result) },
            onToggleCopy: {
                viewModel.toggleImageSelection(result)
            },
            onShowInFinder: {
                NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "")
            },
            showAIBadge: viewModel.aiEnabled && result.matchSource != .exact
        )
    }

    private func moveSelection(by delta: Int) {
        guard !viewModel.results.isEmpty else { return }
        let current = selectedIndex ?? -1
        let next = current + delta
        if next >= 0 && next < viewModel.results.count {
            selectedIndex = next
        }
    }

    private func openSelected() {
        guard !viewModel.results.isEmpty else { return }
        let index = selectedIndex ?? 0
        guard index < viewModel.results.count else { return }
        safeOpen(viewModel.results[index])
    }

    /// Open a file with permission error handling
    private func safeOpen(_ result: SearchResult) {
        let fm = FileManager.default
        let path = result.path

        // Check if file still exists
        guard fm.fileExists(atPath: path) else {
            showPermissionAlert(
                title: "File Not Found",
                message: "The file \"\(result.name)\" no longer exists at:\n\(path)"
            )
            return
        }

        // Check read permission
        guard fm.isReadableFile(atPath: path) else {
            showPermissionAlert(
                title: "Permission Denied",
                message: "BetterSearch can't open \"\(result.name)\" because you don't have permission.\n\nWould you like to grant access?",
                showGrantButton: true,
                filePath: path
            )
            return
        }

        // Try to open
        let success = NSWorkspace.shared.open(result.url)
        if !success {
            showPermissionAlert(
                title: "Unable to Open",
                message: "macOS couldn't open \"\(result.name)\".\n\nThe file may require a specific app or permission to open.",
                showGrantButton: true,
                filePath: path
            )
        }
    }

    private func showPermissionAlert(title: String, message: String, showGrantButton: Bool = false, filePath: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning

        if showGrantButton {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Open Privacy & Security settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            case .alertSecondButtonReturn:
                // Show in Finder — user can open manually
                if let path = filePath {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            default:
                break
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Keyboard handler compatible with macOS 12+

struct KeyPressHandler: ViewModifier {
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.upArrow) { onUp(); return .handled }
                .onKeyPress(.downArrow) { onDown(); return .handled }
                .onKeyPress(.return) { onReturn(); return .handled }
        } else {
            content.background(
                KeyEventView(onUp: onUp, onDown: onDown, onReturn: onReturn)
                    .frame(width: 0, height: 0)
            )
        }
    }
}

/// NSView-based key event handler for macOS 12/13
struct KeyEventView: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onUp = onUp
        view.onDown = onDown
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onReturn = onReturn
    }

    class KeyCatcherView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onReturn: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onUp?()       // up arrow
            case 125: onDown?()     // down arrow
            case 36: onReturn?()    // return
            default: super.keyDown(with: event)
            }
        }
    }
}
