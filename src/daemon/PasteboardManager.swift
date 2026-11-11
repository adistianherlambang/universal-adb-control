import Foundation
import AppKit
import CryptoKit

public enum MacClipContent {
    case text(plain: String, html: String?)
    case image(data: Data, mime: String, filename: String)
    case files(urls: [URL])
    case none
}

public final class PasteboardManager {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1

    public init() {
        lastChangeCount = pasteboard.changeCount
    }

    public func hasChange() -> Bool {
        let current = pasteboard.changeCount
        if current != lastChangeCount {
            lastChangeCount = current
            return true
        }
        return false
    }

    public func getCurrentContent() -> (MacClipContent, String)? {
        // 1. Check for file URLs first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            // Check if it's actually files or an image copied as file
            let existingFiles = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
            if !existingFiles.isEmpty {
                // If single file and is image, treat as image or files
                if existingFiles.count == 1 {
                    let path = existingFiles[0].path.lowercased()
                    if path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") {
                        if let imgData = try? Data(contentsOf: existingFiles[0]) {
                            let mime = path.hasSuffix(".png") ? "image/png" : "image/jpeg"
                            let hash = computeSha256(data: imgData)
                            return (.image(data: imgData, mime: mime, filename: existingFiles[0].lastPathComponent), hash)
                        }
                    }
                }
                let sortedPaths = existingFiles.map { $0.path }.sorted().joined(separator: ";")
                let hash = computeSha256(data: sortedPaths.data(using: .utf8) ?? Data())
                return (.files(urls: existingFiles), hash)
            }
        }

        // 2. Check for Direct Image in Pasteboard
        if let imgData = pasteboard.data(forType: .png) {
            let hash = computeSha256(data: imgData)
            return (.image(data: imgData, mime: "image/png", filename: "clipboard.png"), hash)
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            if let imageRep = NSBitmapImageRep(data: tiffData),
               let pngData = imageRep.representation(using: .png, properties: [:]) {
                let hash = computeSha256(data: pngData)
                return (.image(data: pngData, mime: "image/png", filename: "clipboard.png"), hash)
            }
        }

        // 3. Check for HTML / Rich Text
        let html = pasteboard.string(forType: .html)

        // 4. Check for Plain Text
        if let plain = pasteboard.string(forType: .string), !plain.isEmpty {
            let combined = (html ?? "") + "::" + plain
            let hash = computeSha256(data: combined.data(using: .utf8) ?? Data())
            return (.text(plain: plain, html: html), hash)
        }

        return nil
    }

    public func writeText(plain: String, html: String?) {
        pasteboard.clearContents()
        if let h = html, !h.isEmpty {
            let item = NSPasteboardItem()
            item.setString(h, forType: .html)
            item.setString(plain, forType: .string)
            pasteboard.writeObjects([item])
        } else {
            pasteboard.setString(plain, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    public func writeImage(fileUrl: URL) {
        pasteboard.clearContents()
        guard let image = NSImage(contentsOf: fileUrl) else { return }
        pasteboard.writeObjects([image, fileUrl as NSURL])
        lastChangeCount = pasteboard.changeCount
    }

    public func writeFiles(urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        lastChangeCount = pasteboard.changeCount
    }

    private func computeSha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
