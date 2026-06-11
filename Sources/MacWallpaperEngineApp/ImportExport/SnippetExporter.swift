import AVFoundation
import Foundation
import MacWallpaperEngineCore

enum SnippetExporter {
    static func exportOptimizedSnippet(
        sourceURL: URL,
        assetID: UUID,
        sourceDisplayName: String,
        duration: Double,
        trim: VideoTrimConfiguration
    ) async throws -> URL {
        let snippet = trim.performanceSnippet(forDuration: duration)
        let start = CMTime(seconds: snippet.startSeconds, preferredTimescale: 600)
        let end = CMTime(seconds: snippet.effectiveEndSeconds(forDuration: duration), preferredTimescale: 600)
        let timeRange = CMTimeRange(start: start, end: end)

        let directory = try optimizedDirectory()
        let safeName = sourceDisplayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputURL = directory
            .appendingPathComponent("\(safeName)-\(assetID.uuidString.prefix(8))-optimized")
            .appendingPathExtension("mov")

        try? FileManager.default.removeItem(at: outputURL)

        let sourceAsset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.missingVideoTrack
        }

        try videoTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
        videoTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)

        if let audioSourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(timeRange, of: audioSourceTrack, at: .zero)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.cannotCreateExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed, .cancelled:
            throw exportSession.error ?? ExportError.exportFailed
        default:
            throw ExportError.exportFailed
        }
    }

    private static func optimizedDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL
            .appendingPathComponent("MacWallpaperEngine", isDirectory: true)
            .appendingPathComponent("OptimizedSnippets", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    enum ExportError: LocalizedError {
        case missingVideoTrack
        case cannotCreateExportSession
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                "The source video does not contain a video track."
            case .cannotCreateExportSession:
                "Could not create an optimized export session."
            case .exportFailed:
                "The optimized snippet export did not complete."
            }
        }
    }
}
