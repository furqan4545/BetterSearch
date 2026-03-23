import AppKit
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "indexer")

/// Lightweight file entry for in-memory index
struct IndexedFile {
    let name: String
    let nameLower: String
    let path: String
    let score: Int
}

/// In-memory file index. Scans user folders on launch for instant search.
/// Uses FSEvents to auto-update when files are created, deleted, or renamed.
class FileIndexer {
    static let shared = FileIndexer()

    private var files: [IndexedFile] = []
    private var fileSet: Set<String> = []  // Fast lookup for dedup
    private(set) var ready = false
    private(set) var count: Int = 0
    private let queue = DispatchQueue(label: "fileIndexer", qos: .utility)
    private var eventStream: FSEventStreamRef?

    private let scanFolders: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Desktop",
            "\(home)/Downloads",
            "\(home)/Documents",
            "\(home)/Music",
            "\(home)/Movies",
            "\(home)/Pictures",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }()

    /// Build index by scanning user folders with FileManager (parallel per folder)
    func buildIndex() {
        let folders = scanFolders
        let group = DispatchGroup()
        var allFiles: [[IndexedFile]] = Array(repeating: [], count: folders.count)

        let start = CFAbsoluteTimeGetCurrent()

        for (i, folder) in folders.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                var folderFiles: [IndexedFile] = []
                let fm = FileManager.default
                let url = URL(fileURLWithPath: folder)

                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { return }

                var depth = 0
                let maxDepth = 6

                for case let fileURL as URL in enumerator {
                    // Skip deep nesting
                    if enumerator.level > maxDepth {
                        enumerator.skipDescendants()
                        continue
                    }

                    // Skip node_modules, .git, etc
                    let lastComponent = fileURL.lastPathComponent
                    if lastComponent == "node_modules" || lastComponent == ".git" || lastComponent == "Pods" {
                        enumerator.skipDescendants()
                        continue
                    }

                    let name = lastComponent
                    let path = fileURL.path
                    let score = Self.tierScore(path: path, name: name)

                    folderFiles.append(IndexedFile(
                        name: name,
                        nameLower: name.lowercased(),
                        path: path,
                        score: score
                    ))
                }

                allFiles[i] = folderFiles
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }

            // Scan /Applications separately — .app bundles are packages so enumerator skips them
            var appFiles: [IndexedFile] = []
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path

            for appDir in ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", "\(home)/Applications"] {
                guard let contents = try? fm.contentsOfDirectory(atPath: appDir) else { continue }
                for item in contents where item.hasSuffix(".app") {
                    let path = "\(appDir)/\(item)"
                    appFiles.append(IndexedFile(
                        name: item,
                        nameLower: item.lowercased(),
                        path: path,
                        score: 5
                    ))
                }
            }

            self.files = allFiles.flatMap { $0 } + appFiles
            self.fileSet = Set(self.files.map { $0.path })
            self.count = self.files.count
            self.ready = true
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            logger.warning("Index built: \(self.count) files (\(appFiles.count) apps) in \(String(format: "%.2f", elapsed))s")

            // Start watching for file system changes
            self.startFSEventsWatcher()
        }
    }

    // MARK: - FSEvents file system watcher

    private func startFSEventsWatcher() {
        let paths = scanFolders as CFArray
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 second latency — batches rapid changes
            flags
        ) else {
            logger.error("Failed to create FSEventStream")
            return
        }

        self.eventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        logger.warning("FSEvents watcher started for \(self.scanFolders.count) folders")
    }

    /// Handle file system events — add/remove files from index
    fileprivate func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        var changed = false

        for (i, path) in paths.enumerated() {
            let flag = flags[i]
            let name = (path as NSString).lastPathComponent

            // Skip hidden files and junk
            if name.hasPrefix(".") { continue }
            if path.contains("/node_modules/") || path.contains("/.git/") { continue }

            let isRemoved = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
            let isRenamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
            let isCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isModified = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isDir = (flag & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0

            if isRemoved || (isRenamed && !FileManager.default.fileExists(atPath: path)) {
                // File removed — remove from index
                if fileSet.contains(path) {
                    files.removeAll { $0.path == path }
                    fileSet.remove(path)
                    changed = true
                }
            } else if isCreated || isRenamed || isModified {
                // File created or appeared — add to index if not already there
                guard FileManager.default.fileExists(atPath: path) else { continue }
                if !fileSet.contains(path) {
                    let score = Self.tierScore(path: path, name: name)
                    let entry = IndexedFile(name: name, nameLower: name.lowercased(), path: path, score: score)
                    files.append(entry)
                    fileSet.insert(path)
                    changed = true

                    // If it's a new directory, scan its contents
                    if isDir {
                        scanNewDirectory(at: path)
                    }
                }
            }
        }

        if changed {
            count = files.count
            logger.warning("Index updated: \(self.count) files (live)")
        }
    }

    /// Scan a newly created directory and add its contents to the index
    private func scanNewDirectory(at dirPath: String) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: dirPath),
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if enumerator.level > 6 { enumerator.skipDescendants(); continue }
            let name = fileURL.lastPathComponent
            if name == "node_modules" || name == ".git" { enumerator.skipDescendants(); continue }

            let path = fileURL.path
            if !fileSet.contains(path) {
                let score = Self.tierScore(path: path, name: name)
                files.append(IndexedFile(name: name, nameLower: name.lowercased(), path: path, score: score))
                fileSet.insert(path)
            }
        }
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Search in-memory index — sub-millisecond
    /// Supports multi-word queries: "screen studio" matches "Screen_studio_sample.mp4"
    func search(term: String, limit: Int = 200) -> [SearchResult] {
        guard ready else { return [] }

        let termLower = term.lowercased()
        let searchWords = termLower.components(separatedBy: " ").filter { !$0.isEmpty }
        let start = CFAbsoluteTimeGetCurrent()

        var matches: [(file: IndexedFile, matchScore: Int)] = []
        matches.reserveCapacity(500)

        for file in files {
            // Normalize filename: replace separators with spaces for matching
            let normalizedName = file.nameLower
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: ".", with: " ")

            // Multi-word: ALL words must appear in filename (or path)
            let allMatch: Bool
            if searchWords.count > 1 {
                allMatch = searchWords.allSatisfy { word in
                    file.nameLower.contains(word) || normalizedName.contains(word)
                }
            } else {
                allMatch = file.nameLower.contains(termLower) || normalizedName.contains(termLower)
            }

            guard allMatch else { continue }

            var score = file.score
            let nameNoExt = (file.nameLower as NSString).deletingPathExtension
            let nameNoExtNormalized = nameNoExt
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            // Exact match bonus
            if nameNoExt == termLower || nameNoExtNormalized == termLower {
                score -= 100
            } else if file.nameLower.hasPrefix(searchWords[0]) || normalizedName.hasPrefix(searchWords[0]) {
                score -= 50
            }

            // Bonus if all words appear consecutively (tighter match)
            if searchWords.count > 1 {
                let joined = searchWords.joined(separator: "")
                let nameCompact = nameNoExt.replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: " ", with: "")
                if nameCompact.contains(joined) {
                    score -= 30
                }
            }

            matches.append((file, max(0, score)))
        }

        matches.sort { $0.matchScore < $1.matchScore }

        let results = matches.prefix(limit).map { match -> SearchResult in
            SearchResult(
                id: match.file.path,
                name: match.file.name,
                path: match.file.path,
                url: URL(fileURLWithPath: match.file.path),
                icon: nil
            )
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.warning("Search '\(term)': \(matches.count) matches in \(String(format: "%.1f", elapsed))ms")

        return results
    }

    /// Fuzzy search — finds typos like "safri" → "Safari"
    func fuzzySearch(term: String, limit: Int = 30) -> [SearchResult] {
        guard ready else { return [] }

        let termLower = term.lowercased()
        var matches: [(file: IndexedFile, dist: Int)] = []

        for file in files {
            // Skip if already an exact match (handled by layer 1)
            if file.nameLower.contains(termLower) { continue }

            if FuzzyMatcher.isFuzzyMatch(term: termLower, fileName: file.nameLower) {
                let nameNoExt = (file.nameLower as NSString).deletingPathExtension
                let dist = FuzzyMatcher.levenshtein(termLower, nameNoExt)
                matches.append((file, dist))
            }
        }

        matches.sort { $0.dist < $1.dist }

        return matches.prefix(limit).map { match in
            SearchResult(
                id: match.file.path,
                name: match.file.name,
                path: match.file.path,
                url: URL(fileURLWithPath: match.file.path),
                icon: nil,
                matchSource: .fuzzy
            )
        }
    }

    /// Search by file extensions (for category detection)
    func searchByExtensions(extensions: Set<String>, limit: Int = 100) -> [SearchResult] {
        guard ready else { return [] }

        var matches: [(file: IndexedFile, score: Int)] = []

        for file in files {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if extensions.contains(ext) {
                matches.append((file, file.score))
            }
        }

        matches.sort { $0.score < $1.score }

        return matches.prefix(limit).map { match in
            SearchResult(
                id: match.file.path,
                name: match.file.name,
                path: match.file.path,
                url: URL(fileURLWithPath: match.file.path),
                icon: nil,
                matchSource: .category
            )
        }
    }

    /// Pre-computed file type tier score
    static func tierScore(path: String, name: String) -> Int {
        let ext = (name as NSString).pathExtension.lowercased()
        let pathLower = path.lowercased()

        if pathLower.contains("/node_modules/") { return 900 }
        if pathLower.contains("/.git/") { return 900 }
        if pathLower.contains("/cache") || pathLower.contains("/caches") { return 850 }
        if pathLower.contains("/dist/") || pathLower.contains("/build/") { return 750 }

        let tier1: Set<String> = [
            "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "svg", "ico", "raw",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "keynote",
            "txt", "rtf", "odt", "ods", "odp", "csv",
            "mp3", "mp4", "mov", "avi", "mkv", "wav", "aac", "flac", "m4a", "m4v", "wmv",
            "zip", "rar", "7z", "tar", "gz", "dmg", "iso",
            "app", "pkg", "exe",
        ]

        let tier2: Set<String> = [
            "html", "css", "json", "xml", "md", "yaml", "yml", "toml", "ini", "cfg", "conf",
            "log", "sql", "sh", "bash", "zsh", "plist",
        ]

        let tier3: Set<String> = [
            "swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "c", "cpp", "h", "hpp",
            "go", "rs", "rb", "php", "cs", "m", "mm", "r", "scala", "dart", "lua",
            "mjs", "cjs", "vue", "svelte",
        ]

        // Apps get absolute top priority
        if ext == "app" { return 5 }

        var score: Int
        if tier1.contains(ext) { score = 50 }
        else if tier2.contains(ext) { score = 250 }
        else if tier3.contains(ext) { score = 450 }
        else if name.hasSuffix(".d.ts") || name.hasSuffix(".min.js") || ext == "map" || ext == "pyc" { score = 650 }
        else if ext.isEmpty { score = 40 }
        else { score = 500 }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["/Desktop/", "/Downloads/", "/Documents/"] {
            if path.hasPrefix(home + folder) { score -= 30; break }
        }

        let depth = path.components(separatedBy: "/").count
        if depth <= 5 { score -= 20 }
        else if depth > 10 { score += 20 }

        return max(0, score)
    }
}

// MARK: - FSEvents C callback (must be a free function)

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let indexer = Unmanaged<FileIndexer>.fromOpaque(info).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

    DispatchQueue.main.async {
        indexer.handleFSEvents(paths: paths, flags: flags)
    }
}
