import AppKit
import Combine
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "search")

class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchTimeMs: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var searchID: UUID = UUID()

    init() {
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] term in
                self?.performSearch(term: term)
            }
            .store(in: &cancellables)
    }

    private func performSearch(term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        let thisSearchID = UUID()
        searchID = thisSearchID

        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            searchTimeMs = 0
            return
        }

        let indexer = FileIndexer.shared

        if indexer.ready {
            // ⚡ IN-MEMORY SEARCH — sub-millisecond
            let start = CFAbsoluteTimeGetCurrent()
            let results = indexer.search(term: trimmed, limit: 200)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            self.results = results
            self.searchTimeMs = elapsed
            self.isSearching = false
        } else {
            // Fallback: mdfind while index is building
            isSearching = true
            results = []

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let start = CFAbsoluteTimeGetCurrent()
                let paths = Self.runMdfind(term: trimmed)
                let results = Self.buildAndRank(paths: paths, searchTerm: trimmed.lowercased())
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

                DispatchQueue.main.async {
                    guard let self, self.searchID == thisSearchID else { return }
                    self.results = results
                    self.searchTimeMs = elapsed
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - mdfind fallback

    private static let junkPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library", "/System", "/Library", "/private", "/usr", "/var",
        ]
    }()

    nonisolated static func runMdfind(term: String) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", term]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return [] }

        // 3 second timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .filter { path in !junkPrefixes.contains(where: { path.hasPrefix($0) }) }
    }

    nonisolated static func buildAndRank(paths: [String], searchTerm: String) -> [SearchResult] {
        var results = Array(paths.prefix(200)).compactMap { path -> SearchResult? in
            let url = URL(fileURLWithPath: path)
            return SearchResult(id: path, name: url.lastPathComponent, path: path, url: url, icon: nil)
        }

        results.sort { a, b in
            scoreResult(a, searchTerm: searchTerm) < scoreResult(b, searchTerm: searchTerm)
        }
        return results
    }

    nonisolated static func scoreResult(_ r: SearchResult, searchTerm: String) -> Int {
        var score = FileIndexer.tierScore(path: r.path, name: r.name)
        let nameNoExt = (r.name as NSString).deletingPathExtension.lowercased()
        if nameNoExt == searchTerm { score -= 100 }
        else if r.name.lowercased().hasPrefix(searchTerm) { score -= 50 }
        return max(0, score)
    }
}
