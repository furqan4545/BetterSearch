import AppKit
import QuickLookThumbnailing

struct SearchResult: Identifiable {
    let id: String
    let name: String
    let path: String
    let url: URL
    let icon: NSImage?

    var resolvedIcon: NSImage {
        if let icon { return icon }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 32, height: 32)
        return img
    }

    /// File extensions that support real thumbnails
    static let thumbnailExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "svg", "ico", "raw",
        "mp4", "mov", "avi", "mkv", "m4v", "wmv",
        "pdf", "psd", "ai",
        "pages", "numbers", "keynote", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    ]

    var supportsThumbnail: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return Self.thumbnailExtensions.contains(ext)
    }
}

/// SwiftUI view that loads a real thumbnail async, falls back to file icon
import SwiftUI

struct ThumbnailView: View {
    let result: SearchResult
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(nsImage: result.resolvedIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard result.supportsThumbnail else { return }

        let request = QLThumbnailGenerator.Request(
            fileAt: result.url,
            size: CGSize(width: 72, height: 72),
            scale: 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, type, error in
            if let rep {
                DispatchQueue.main.async {
                    self.thumbnail = rep.nsImage
                }
            }
        }
    }
}
