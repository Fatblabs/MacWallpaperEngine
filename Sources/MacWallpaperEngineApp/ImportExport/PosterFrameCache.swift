import AppKit
import AVFoundation
import Foundation

enum PosterFrameCache {
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

        let url = directory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    static func remove(filename: String?) {
        guard let filename,
              let directory = try? posterDirectory() else {
            return
        }

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
