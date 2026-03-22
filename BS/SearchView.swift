import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onDismiss: () -> Void = {}

    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if viewModel.isSearching && viewModel.results.isEmpty {
                Divider()
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
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result: result, index: index)
                            if index < viewModel.results.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            if !viewModel.isSearching && viewModel.results.isEmpty && viewModel.searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                Divider()
                Text("No results found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }

            // Search speed indicator
            if !viewModel.results.isEmpty && viewModel.searchTimeMs > 0 {
                Divider()
                HStack {
                    Text("\(viewModel.results.count) results in \(String(format: "%.1f", viewModel.searchTimeMs))ms")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if FileIndexer.shared.ready {
                        Text("⚡ indexed")
                            .font(.system(size: 10))
                            .foregroundStyle(.green.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            }
        }
        .frame(width: 680)
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("Search files...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light, design: .rounded))

            // AI Toggle
            Button(action: { viewModel.aiEnabled.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.aiEnabled ? "sparkles" : "magnifyingglass")
                        .font(.system(size: 14))
                    Text("AI")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(viewModel.aiEnabled ? Color.purple.opacity(0.3) : Color.gray.opacity(0.2))
                .foregroundStyle(viewModel.aiEnabled ? .purple : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(viewModel.aiEnabled ? "AI Search: ON (fuzzy, semantic, category, content)" : "AI Search: OFF (exact match only)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func resultRow(result: SearchResult, index: Int) -> some View {
        HStack(spacing: 12) {
            ThumbnailView(result: result)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(1)

                Text(result.path)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if viewModel.aiEnabled && result.matchSource != .exact {
                matchBadge(source: result.matchSource)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedIndex == index ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(result.url)
        }
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(result.url)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "")
            }
        }
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
        NSWorkspace.shared.open(viewModel.results[index].url)
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
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
