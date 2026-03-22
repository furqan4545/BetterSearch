import AppKit
import Combine
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "search")

class SearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchTimeMs: Double = 0
    @Published var aiEnabled: Bool = true  // 🧠 AI Toggle — controls smart search layers
    @Published var selectedImagePaths: Set<String> = []  // Multi-select for copy

    /// Toggle image selection and update clipboard with all selected images
    func toggleImageSelection(_ result: SearchResult) {
        if selectedImagePaths.contains(result.path) {
            selectedImagePaths.remove(result.path)
        } else {
            selectedImagePaths.insert(result.path)
        }
        copySelectedImagesToClipboard()
    }

    /// Copy all selected images to clipboard
    private func copySelectedImagesToClipboard() {
        guard !selectedImagePaths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()

        var objects: [NSPasteboardWriting] = []
        for path in selectedImagePaths {
            let url = URL(fileURLWithPath: path)
            objects.append(url as NSURL)
            if let image = NSImage(contentsOfFile: path) {
                objects.append(image)
            }
        }
        pb.writeObjects(objects)
    }

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
        selectedImagePaths.removeAll()

        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            searchTimeMs = 0
            return
        }

        let indexer = FileIndexer.shared

        if aiEnabled {
            performSmartSearch(term: trimmed, searchID: thisSearchID)
        } else {
            performBasicSearch(term: trimmed, searchID: thisSearchID)
        }
    }

    // MARK: - Basic Search (AI OFF) — original behavior

    private func performBasicSearch(term: String, searchID: UUID) {
        let indexer = FileIndexer.shared

        if indexer.ready {
            let start = CFAbsoluteTimeGetCurrent()
            let results = indexer.search(term: term, limit: 200)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            self.results = results
            self.searchTimeMs = elapsed
            self.isSearching = false
        } else {
            isSearching = true
            results = []

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let start = CFAbsoluteTimeGetCurrent()
                let paths = Self.runMdfind(term: term)
                let results = Self.buildAndRank(paths: paths, searchTerm: term.lowercased())
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

                DispatchQueue.main.async {
                    guard let self, self.searchID == searchID else { return }
                    self.results = results
                    self.searchTimeMs = elapsed
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - Smart Search (AI ON) — all 5 layers, streaming

    /// Thread-safe seen paths tracker (only mutated on main thread)
    private var seenPaths = Set<String>()

    private func performSmartSearch(term: String, searchID: UUID) {
        let start = CFAbsoluteTimeGetCurrent()
        let termLower = term.lowercased()
        let indexer = FileIndexer.shared

        isSearching = true
        results = []
        seenPaths = Set<String>()

        guard indexer.ready else {
            performBasicSearch(term: term, searchID: searchID)
            return
        }

        // ═══════════════════════════════════════════════════════
        // LAYER 1: Exact match (sub-millisecond, in-memory)
        // ═══════════════════════════════════════════════════════
        let exactResults = indexer.search(term: term, limit: 50)
        for r in exactResults { seenPaths.insert(r.path) }
        self.results = exactResults
        self.isSearching = false
        self.searchTimeMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.warning("L1 exact: \(exactResults.count) results in \(String(format: "%.1f", self.searchTimeMs))ms")

        // ═══════════════════════════════════════════════════════
        // LAYER 4: Category detection (instant, in-memory)
        // ═══════════════════════════════════════════════════════
        if let categoryExts = CategoryDetector.detect(term: term) {
            let categoryResults = indexer.searchByExtensions(extensions: categoryExts, limit: 100)
            let filtered = categoryResults.filter { seenPaths.insert($0.path).inserted }
                .map { var r = $0; r.matchSource = .category; return r }
            self.mergeResults(filtered)
            logger.warning("L4 category: \(filtered.count) results")
        }

        // ═══════════════════════════════════════════════════════
        // LAYER 2: Fuzzy match (background work, main thread append)
        // ═══════════════════════════════════════════════════════
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fuzzyResults = indexer.fuzzySearch(term: termLower, limit: 30)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.searchID == searchID else { return }
                let newFuzzy = fuzzyResults.filter { self.seenPaths.insert($0.path).inserted }
                    .map { var r = $0; r.matchSource = .fuzzy; return r }
                if !newFuzzy.isEmpty {
                    self.mergeResults(newFuzzy)
                    logger.warning("L2 fuzzy: \(newFuzzy.count) results")
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        // LAYER 3: NLEmbedding semantic (background work, main thread append)
        // ═══════════════════════════════════════════════════════
        DispatchQueue.global(qos: .userInitiated).async {
            let words = term.lowercased().components(separatedBy: " ")
            var allSimilar: [String] = []
            for word in words where word.count >= 3 {
                let similar = SemanticSearch.shared.findSimilarWords(to: word, maxResults: 5)
                allSimilar.append(contentsOf: similar)
            }

            guard !allSimilar.isEmpty else { return }
            logger.warning("L3 semantic words for '\(term)': \(allSimilar)")

            var semanticResults: [SearchResult] = []
            for word in allSimilar {
                let found = indexer.search(term: word, limit: 10)
                semanticResults.append(contentsOf: found)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.searchID == searchID else { return }
                let newSemantic = semanticResults.filter { self.seenPaths.insert($0.path).inserted }
                    .map { var r = $0; r.matchSource = .semantic; return r }
                if !newSemantic.isEmpty {
                    self.mergeResults(newSemantic)
                    logger.warning("L3 semantic: \(newSemantic.count) results")
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        // LAYER 5: Spotlight content search (async, ~200ms)
        // ═══════════════════════════════════════════════════════
        SpotlightContentSearch.search(term: term, limit: 30) { [weak self] contentResults in
            guard let self, self.searchID == searchID else { return }
            let newContent = contentResults.filter { self.seenPaths.insert($0.path).inserted }
            if !newContent.isEmpty {
                self.mergeResults(newContent)
                logger.warning("L5 content: \(newContent.count) results")
            }
            self.searchTimeMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
    }

    // MARK: - Smart merge: insert new results at the right position by score

    private func mergeResults(_ newResults: [SearchResult]) {
        guard !newResults.isEmpty else { return }
        results.append(contentsOf: newResults)
        // Re-sort: exact matches stay on top, then sort by tier score within each match source
        results.sort { a, b in
            let scoreA = Self.combinedScore(a)
            let scoreB = Self.combinedScore(b)
            return scoreA < scoreB
        }
    }

    /// Combined score: matchSource priority + file tier score
    nonisolated private static func combinedScore(_ r: SearchResult) -> Int {
        // Match source priority (lower = better)
        let sourcePriority: Int
        switch r.matchSource {
        case .exact: sourcePriority = 0
        case .category: sourcePriority = 100
        case .fuzzy: sourcePriority = 200
        case .semantic: sourcePriority = 300
        case .contentMatch: sourcePriority = 400
        }

        let tierScore = FileIndexer.tierScore(path: r.path, name: r.name)

        // For fuzzy/semantic: if file is tier1 (apps, images, docs), boost it significantly
        // so a fuzzy match on Arc.app ranks higher than exact match on learningv1.entitlements
        if r.matchSource == .fuzzy || r.matchSource == .semantic {
            if tierScore <= 50 {
                // High priority file (app, image, doc, video) — promote it
                return sourcePriority / 2 + tierScore
            }
        }

        return sourcePriority + tierScore
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
