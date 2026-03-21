import AppKit

struct SearchResult: Identifiable {
    let id: String
    let name: String
    let path: String
    let url: URL
    let icon: NSImage
}
