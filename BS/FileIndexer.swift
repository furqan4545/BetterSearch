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
class FileIndexer {
    static let shared = FileIndexer()

    private var files: [IndexedFile] = []
    private(set) var ready = false
    private(set) var count: Int = 0
    private let queue = DispatchQueue(label: "fileIndexer", qos: .utility)

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
            self.count = self.files.count
            self.ready = true
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            logger.warning("Index built: \(self.count) files (\(appFiles.count) apps) in \(String(format: "%.2f", elapsed))s")
        }
    }

    /// Search in-memory index — sub-millisecond
    func search(term: String, limit: Int = 200) -> [SearchResult] {
        guard ready else { return [] }

        let termLower = term.lowercased()
        let start = CFAbsoluteTimeGetCurrent()

        var matches: [(file: IndexedFile, matchScore: Int)] = []
        matches.reserveCapacity(500)

        for file in files {
            guard file.nameLower.contains(termLower) else { continue }

            var score = file.score
            let nameNoExt = (file.nameLower as NSString).deletingPathExtension
            if nameNoExt == termLower {
                score -= 100
            } else if file.nameLower.hasPrefix(termLower) {
                score -= 50
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
