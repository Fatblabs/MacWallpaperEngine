import AppKit
import AVFoundation
import Foundation

@MainActor
enum PosterFrameCache {
    private static let imageCache = NSCache<NSString, NSImage>()

    static func generatePoster(for url: URL, assetID: UUID) -> String? {
        do {
            let directory = try posterDirectory()
            let filename = "\(assetID.uuidString).png"
            let outputURL = directory.appendingPathComponent(filename)

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)

            let image = try generator.copyCGImage(
                at: CMTime(seconds: 1, preferredTimescale: 600),
                actualTime: nil
            )
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }

            try data.write(to: outputURL, options: .atomic)
            imageCache.setObject(NSImage(cgImage: image, size: .zero), forKey: filename as NSString)
            return filename
        } catch {
            return nil
        }
    }

    static func image(for filename: String?) -> NSImage? {
        guard let filename,
              let directory = try? posterDirectory() else {
            return nil
        }

        if let cachedImage = imageCache.object(forKey: filename as NSString) {
            return cachedImage
        }

        let url = directory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func remove(filename: String?) {
        guard let filename,
              let directory = try? posterDirectory() else {
            return
        }

        imageCache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    private static func posterDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL
            .appendingPathComponent("MacWallpaperEngine", isDirectory: true)
            .appendingPathComponent("Posters", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
