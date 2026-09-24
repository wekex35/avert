import AppKit
import Foundation
import UniformTypeIdentifiers

/// Stores an optional panic cover image in Application Support.
@MainActor
final class PanicImageStore {
    private let fileManager = FileManager.default

    private var directoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Avert", isDirectory: true)
    }

    private var imageURL: URL {
        directoryURL.appendingPathComponent("panic-cover.jpg")
    }

    var hasImage: Bool {
        fileManager.fileExists(atPath: imageURL.path)
    }

    func loadImage() -> NSImage? {
        guard hasImage else { return nil }
        return NSImage(contentsOf: imageURL)
    }

    @discardableResult
    func importImage(from source: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: imageURL.path) {
                try fileManager.removeItem(at: imageURL)
            }
            // Prefer JPEG copy for a stable path; fall back to raw copy.
            if let image = NSImage(contentsOf: source),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                try data.write(to: imageURL, options: .atomic)
            } else {
                try fileManager.copyItem(at: source, to: imageURL)
            }
            return true
        } catch {
            return false
        }
    }

    func clear() {
        try? fileManager.removeItem(at: imageURL)
    }

    func pickImageFromUser() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image for look-up / panic cover"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return importImage(from: url)
    }
}
