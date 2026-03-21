import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onDismiss: () -> Void = {}

    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !viewModel.results.isEmpty || viewModel.isSearching {
                Divider().background(Color.white.opacity(0.2))
                resultsList
            }
        }
        .frame(width: 680)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)

            TextField("Search files...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .onSubmit { openSelected() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isSearching && viewModel.results.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Searching...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if !viewModel.isSearching && viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
                    Text("No results found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result: result, index: index)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func resultRow(result: SearchResult, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: result.icon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(result.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(selectedIndex == index ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(result.url)
            onDismiss()
        }
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(result.url)
                onDismiss()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "")
                onDismiss()
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
        guard let index = selectedIndex, index < viewModel.results.count else {
            if let first = viewModel.results.first {
                NSWorkspace.shared.open(first.url)
                onDismiss()
            }
            return
        }
        NSWorkspace.shared.open(viewModel.results[index].url)
        onDismiss()
    }
}
