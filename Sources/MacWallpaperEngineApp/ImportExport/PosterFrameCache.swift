import AppKit
import AVFoundation
import Foundation

@MainActor
enum PosterFrameCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func generatePoster(for url: URL, assetID: UUID) async -> String? {
        do {
            let directory = try posterDirectory()
            let filename = "\(assetID.uuidString).png"
            let outputURL = directory.appendingPathComponent(filename)

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)

            let image = try await generator.image(at: .zero).image
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }

            try data.write(to: outputURL, options: .atomic)
            imageCache.setObject(NSImage(cgImage: image, size: .zero), forKey: filename as NSString,
                                 cost: image.bytesPerRow * image.height)
            return filename
        } catch {
            return nil
        }
    }

    static func image(for filename: String?) -> NSImage? {
        guard let filename, filename == (filename as NSString).lastPathComponent else {
            return nil
        }

        if let cachedImage = imageCache.object(forKey: filename as NSString) {
            return cachedImage
        }
        guard let directory = try? posterDirectory() else { return nil }

        let url = directory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: filename as NSString, cost: 640 * 360 * 4)
        return image
    }

    static func remove(filename: String?) {
        guard let filename, filename == (filename as NSString).lastPathComponent,
              let directory = try? posterDirectory() else {
            return
        }

        imageCache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    private static func posterDirectory() throws -> URL {
        let directory = AppStorage.root
            .appendingPathComponent("Posters", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
