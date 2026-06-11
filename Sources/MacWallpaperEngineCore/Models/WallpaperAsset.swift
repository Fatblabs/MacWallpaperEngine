import AVFoundation
import Foundation
import UniformTypeIdentifiers

public struct WallpaperAsset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var originalFilename: String
    public var bookmarkData: Data
    public var duration: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var codecSummary: String
    public var lastKnownPath: String
    public var posterFrameFilename: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        originalFilename: String,
        bookmarkData: Data,
        duration: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        codecSummary: String,
        lastKnownPath: String,
        posterFrameFilename: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.bookmarkData = bookmarkData
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.codecSummary = codecSummary
        self.lastKnownPath = lastKnownPath
        self.posterFrameFilename = posterFrameFilename
        self.createdAt = createdAt
    }
}

public enum LocalVideoImportError: LocalizedError, Equatable {
    case notAFileURL
    case unsupportedFileType(String)
    case missingVideoTrack
    case unreadableMovie

    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            "Only local video files are supported."
        case .unsupportedFileType(let pathExtension):
            "Unsupported video type: .\(pathExtension). Choose a local MP4, MOV, M4V, or QuickTime-playable movie."
        case .missingVideoTrack:
            "This file does not contain a playable video track."
        case .unreadableMovie:
            "The selected movie could not be read."
        }
    }
}

public struct ImportedVideoMetadata: Equatable, Sendable {
    public var displayName: String
    public var originalFilename: String
    public var bookmarkData: Data
    public var duration: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var codecSummary: String
    public var lastKnownPath: String

    public init(
        displayName: String,
        originalFilename: String,
        bookmarkData: Data,
        duration: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        codecSummary: String,
        lastKnownPath: String
    ) {
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.bookmarkData = bookmarkData
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.codecSummary = codecSummary
        self.lastKnownPath = lastKnownPath
    }
}

public enum LocalVideoImporter {
    public static let preferredFileExtensions: Set<String> = [
        "mp4",
        "m4v",
        "mov"
    ]

    public static func isSupportedLocalVideoURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return false }

        if preferredFileExtensions.contains(pathExtension) {
            return true
        }

        guard let type = UTType(filenameExtension: pathExtension) else {
            return false
        }

        return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
    }

    public static func metadata(for url: URL) async throws -> ImportedVideoMetadata {
        guard url.isFileURL else {
            throw LocalVideoImportError.notAFileURL
        }

        guard isSupportedLocalVideoURL(url) else {
            throw LocalVideoImportError.unsupportedFileType(url.pathExtension.lowercased())
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw LocalVideoImportError.missingVideoTrack
        }

        let videoSize = try await videoSize(for: videoTrack)
        let width = Int(abs(videoSize.width))
        let height = Int(abs(videoSize.height))
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return ImportedVideoMetadata(
            displayName: url.deletingPathExtension().lastPathComponent,
            originalFilename: url.lastPathComponent,
            bookmarkData: bookmarkData,
            duration: duration.isFinite ? duration : 0,
            pixelWidth: width,
            pixelHeight: height,
            codecSummary: await codecSummary(for: videoTrack),
            lastKnownPath: url.path
        )
    }

    private static func videoSize(for track: AVAssetTrack) async throws -> CGSize {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        return naturalSize.applying(preferredTransform)
    }

    private static func codecSummary(for track: AVAssetTrack) async -> String {
        guard let formatDescriptions = try? await track.load(.formatDescriptions),
              let firstFormatDescription = formatDescriptions.first else {
            return "Video"
        }

        let mediaSubtype = CMFormatDescriptionGetMediaSubType(firstFormatDescription)
        let bytes: [UInt8] = [
            UInt8((mediaSubtype >> 24) & 0xff),
            UInt8((mediaSubtype >> 16) & 0xff),
            UInt8((mediaSubtype >> 8) & 0xff),
            UInt8(mediaSubtype & 0xff)
        ]

        let fourCC = String(bytes: bytes, encoding: .macOSRoman)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fourCC?.isEmpty == false ? fourCC! : "Video"
    }
}
