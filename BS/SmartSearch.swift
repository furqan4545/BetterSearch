import Foundation
import NaturalLanguage
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "smartSearch")

// MARK: - Layer 2: Fuzzy Matching

struct FuzzyMatcher {

    /// Levenshtein distance between two strings
    static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let m = s1.count, n = s2.count
        if m == 0 { return n }
        if n == 0 { return m }

        let a = Array(s1), b = Array(s2)
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }

    /// Check if term is a fuzzy match for filename (max 2 edits for short words, 3 for longer)
    static func isFuzzyMatch(term: String, fileName: String) -> Bool {
        let termLen = term.count
        let maxDist = termLen <= 4 ? 1 : (termLen <= 7 ? 2 : 3)

        let nameNoExt = (fileName as NSString).deletingPathExtension.lowercased()

        // Check against full name
        if nameNoExt.count >= term.count - maxDist && nameNoExt.count <= term.count + maxDist {
            if levenshtein(term, nameNoExt) <= maxDist {
                return true
            }
        }

        // Check against words in filename (split by common separators)
        let words = nameNoExt.components(separatedBy: CharacterSet(charactersIn: " -_.,"))
        for word in words {
            if word.count >= term.count - maxDist && word.count <= term.count + maxDist {
                if levenshtein(term, word) <= maxDist {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Layer 3: NLEmbedding Semantic Search

class SemanticSearch {
    static let shared = SemanticSearch()

    private var embedding: NLEmbedding?

    init() {
        embedding = NLEmbedding.wordEmbedding(for: .english)
        if embedding != nil {
            logger.warning("NLEmbedding loaded successfully")
        } else {
            logger.error("NLEmbedding failed to load")
        }
    }

    /// Find words similar to the search term using Apple's built-in word embeddings
    func findSimilarWords(to term: String, maxResults: Int = 8) -> [String] {
        guard let embedding else { return [] }

        let termLower = term.lowercased()

        // Get nearest neighbors from the embedding space
        var similar: [String] = []
        embedding.enumerateNeighbors(for: termLower, maximumCount: maxResults, distanceType: .cosine) { word, distance in
            // Only include words that are reasonably close (distance < 0.7)
            if distance < 0.7 {
                similar.append(word)
            }
            return true
        }

        return similar
    }
}

// MARK: - Layer 4: Category Detection

struct CategoryDetector {

    struct Category {
        let keywords: [String]
        let extensions: Set<String>
    }

    static let categories: [Category] = [
        Category(
            keywords: ["photo", "photos", "picture", "pictures", "pic", "pics", "image", "images", "img"],
            extensions: ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "svg", "ico", "raw"]
        ),
        Category(
            keywords: ["video", "videos", "movie", "movies", "clip", "clips", "recording", "recordings"],
            extensions: ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm", "flv"]
        ),
        Category(
            keywords: ["music", "song", "songs", "audio", "soundtrack", "podcast"],
            extensions: ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma", "aiff"]
        ),
        Category(
            keywords: ["document", "documents", "doc", "docs", "report", "reports", "paper", "papers", "essay"],
            extensions: ["pdf", "doc", "docx", "txt", "rtf", "odt", "pages"]
        ),
        Category(
            keywords: ["spreadsheet", "spreadsheets", "excel", "sheet", "sheets", "table", "tables", "data"],
            extensions: ["xls", "xlsx", "csv", "numbers", "ods", "tsv"]
        ),
        Category(
            keywords: ["presentation", "presentations", "slides", "slide", "deck", "powerpoint"],
            extensions: ["ppt", "pptx", "keynote", "odp"]
        ),
        Category(
            keywords: ["archive", "archives", "compressed", "zip", "zipped"],
            extensions: ["zip", "rar", "7z", "tar", "gz", "dmg", "iso", "bz2", "xz"]
        ),
        Category(
            keywords: ["code", "script", "scripts", "source", "programming"],
            extensions: ["swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "c", "cpp", "go", "rs", "rb", "php", "html", "css"]
        ),
        Category(
            keywords: ["font", "fonts", "typeface"],
            extensions: ["ttf", "otf", "woff", "woff2"]
        ),
        Category(
            keywords: ["screenshot", "screenshots", "screencap", "screengrab", "screen capture", "screen shot"],
            extensions: ["png", "jpg", "jpeg", "heic"]
        ),
    ]

    /// Detect if the search term matches a category. Returns matching extensions or nil.
    static func detect(term: String) -> Set<String>? {
        let termLower = term.lowercased().trimmingCharacters(in: .whitespaces)
        let words = termLower.components(separatedBy: " ")

        for category in categories {
            for keyword in category.keywords {
                if termLower == keyword || words.contains(keyword) {
                    return category.extensions
                }
            }
        }

        return nil
    }
}

// MARK: - Layer 5: Spotlight Content Search

class SpotlightContentSearch {

    /// Search file contents via mdfind kMDItemTextContent
    static func search(term: String, limit: Int = 50, timeout: TimeInterval = 2.0, completion: @escaping ([SearchResult]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["kMDItemTextContent == '*\(term)*'cd"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do { try process.run() } catch {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let junkPrefixes = ["\(home)/Library", "/System", "/Library", "/private", "/usr", "/var"]

            let paths = output.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .filter { path in !junkPrefixes.contains(where: { path.hasPrefix($0) }) }

            let results = Array(paths.prefix(limit)).compactMap { path -> SearchResult? in
                let url = URL(fileURLWithPath: path)
                return SearchResult(
                    id: "content:\(path)",
                    name: url.lastPathComponent,
                    path: path,
                    url: url,
                    icon: nil,
                    matchSource: .contentMatch
                )
            }

            DispatchQueue.main.async { completion(results) }
        }
    }
}
