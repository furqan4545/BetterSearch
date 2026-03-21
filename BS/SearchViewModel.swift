import AppKit
import Combine

class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching: Bool = false

    private let query = NSMetadataQuery()
    private var cancellables = Set<AnyCancellable>()

    init() {
        query.searchScopes = ["/"]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemFSName", ascending: true)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinish(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] term in
                self?.performSearch(term: term)
            }
            .store(in: &cancellables)
    }

    deinit {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func performSearch(term: String) {
        query.stop()

        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")

        query.predicate = NSPredicate(format: "kMDItemFSName LIKE[cd] %@", "*\(escaped)*")
        query.start()
    }

    @objc private func queryDidFinish(_ notification: Notification) {
        query.disableUpdates()

        var newResults: [SearchResult] = []
        let count = min(query.resultCount, 20)

        for i in 0..<count {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let name = item.value(forAttribute: kMDItemFSName as String) as? String,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else {
                continue
            }

            let url = URL(fileURLWithPath: path)
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 32, height: 32)

            newResults.append(SearchResult(
                id: path,
                name: name,
                path: path,
                url: url,
                icon: icon
            ))
        }

        results = newResults
        isSearching = false
        query.enableUpdates()
    }
}
