import AVFoundation
import Foundation
import MacWallpaperEngineCore

enum SnippetExporter {
    @MainActor
    static func exportOptimizedSnippet(
        sourceURL: URL,
        assetID: UUID,
        sourceDisplayName: String,
        duration: Double,
        trim: VideoTrimConfiguration
    ) async throws -> URL {
        try Task.checkCancellation()
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let snippet = trim.performanceSnippet(forDuration: duration)
        let start = CMTime(seconds: snippet.startSeconds, preferredTimescale: 600)
        let end = CMTime(seconds: snippet.effectiveEndSeconds(forDuration: duration), preferredTimescale: 600)
        let timeRange = CMTimeRange(start: start, end: end)

        let directory = try optimizedDirectory()
        let safeName = sourceDisplayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputURL = directory
            .appendingPathComponent("\(safeName.prefix(100))-\(assetID.uuidString.prefix(8))-optimized-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: outputURL) } }

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
        let cancellation = ExportCancellation(session: exportSession)
        await withTaskCancellationHandler {
            await exportSession.export()
        } onCancel: {
            Task { @MainActor in cancellation.cancel() }
        }
        try Task.checkCancellation()

        switch exportSession.status {
        case .completed:
            completed = true
            return outputURL
        case .failed, .cancelled:
            throw exportSession.error ?? ExportError.exportFailed
        default:
            throw ExportError.exportFailed
        }
    }

    @MainActor
    private final class ExportCancellation {
        let session: AVAssetExportSession
        init(session: AVAssetExportSession) { self.session = session }
        func cancel() { session.cancelExport() }
    }

    private static func optimizedDirectory() throws -> URL {
        let directory = AppStorage.root
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
