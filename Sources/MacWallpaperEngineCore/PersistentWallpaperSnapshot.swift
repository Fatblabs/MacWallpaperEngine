import Foundation

public struct WallpaperAssetRestoreMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var originalFilename: String
    public var lastKnownPath: String
    public var duration: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var codecSummary: String
    public var posterFrameFilename: String?
    public var editorFingerprint: String

    public init(
        displayName: String,
        originalFilename: String,
        lastKnownPath: String,
        duration: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        codecSummary: String,
        posterFrameFilename: String?,
        editorFingerprint: String
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.lastKnownPath = lastKnownPath
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.codecSummary = codecSummary
        self.posterFrameFilename = posterFrameFilename
        self.editorFingerprint = editorFingerprint
    }
}

public struct WallpaperDisplayAssignmentSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String { screenID }
    public var screenID: String
    public var assetID: UUID?
    public var layoutModeRawValue: String

    public init(screenID: String, assetID: UUID?, layoutModeRawValue: String) {
        self.screenID = screenID
        self.assetID = assetID
        self.layoutModeRawValue = layoutModeRawValue
    }
}

public struct PersistentWallpaperSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var activeAssetIDs: [UUID]
    public var assets: [WallpaperAssetRestoreMetadata]
    public var displayAssignments: [WallpaperDisplayAssignmentSnapshot]

    public init(
        updatedAt: Date = Date(),
        activeAssetIDs: [UUID],
        assets: [WallpaperAssetRestoreMetadata],
        displayAssignments: [WallpaperDisplayAssignmentSnapshot]
    ) {
        self.updatedAt = updatedAt
        self.activeAssetIDs = activeAssetIDs
        self.assets = assets
        self.displayAssignments = displayAssignments
    }

    public func assignedAssetID(for screenID: String) -> UUID? {
        displayAssignments.first { $0.screenID == screenID }?.assetID
    }
}

public enum WallpaperReferenceCleanup {
    public static func cleaned(
        configuration: WallpaperEditorConfiguration,
        removing removedAssetID: UUID
    ) -> WallpaperEditorConfiguration {
        var cleaned = configuration

        cleaned.playlist.assetIDs.removeAll { $0 == removedAssetID }
        cleaned.playlist.currentIndex = cleaned.playlist.normalizedCurrentIndex()

        if cleaned.themeSync.lightAssetID == removedAssetID {
            cleaned.themeSync.lightAssetID = nil
        }
        if cleaned.themeSync.darkAssetID == removedAssetID {
            cleaned.themeSync.darkAssetID = nil
        }
        if cleaned.themeSync.dayAssetID == removedAssetID {
            cleaned.themeSync.dayAssetID = nil
        }
        if cleaned.themeSync.nightAssetID == removedAssetID {
            cleaned.themeSync.nightAssetID = nil
        }

        return cleaned
    }
}
