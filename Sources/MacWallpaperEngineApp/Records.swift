import Foundation
import MacWallpaperEngineCore
import SwiftData

@Model
final class WallpaperAssetRecord {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var originalFilename: String
    @Attribute(.externalStorage) var bookmarkData: Data
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var codecSummary: String
    var lastKnownPath: String
    var posterFrameFilename: String?
    @Attribute(.externalStorage) var editorConfigurationData: Data?
    var createdAt: Date

    init(asset: WallpaperAsset) {
        self.id = asset.id
        self.displayName = asset.displayName
        self.originalFilename = asset.originalFilename
        self.bookmarkData = asset.bookmarkData
        self.duration = asset.duration
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.codecSummary = asset.codecSummary
        self.lastKnownPath = asset.lastKnownPath
        self.posterFrameFilename = asset.posterFrameFilename
        self.editorConfigurationData = try? JSONEncoder().encode(WallpaperEditorConfiguration.default)
        self.createdAt = asset.createdAt
    }

    var aspectDescription: String {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return "Unknown size"
        }

        return "\(pixelWidth)x\(pixelHeight)"
    }

    func wallpaperAsset() -> WallpaperAsset {
        WallpaperAsset(
            id: id,
            displayName: displayName,
            originalFilename: originalFilename,
            bookmarkData: bookmarkData,
            duration: duration,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            codecSummary: codecSummary,
            lastKnownPath: lastKnownPath,
            posterFrameFilename: posterFrameFilename,
            createdAt: createdAt
        )
    }

    func resolvedURL() throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }

    var editorConfiguration: WallpaperEditorConfiguration {
        get {
            guard let editorConfigurationData,
                  let decoded = try? JSONDecoder().decode(WallpaperEditorConfiguration.self, from: editorConfigurationData) else {
                return .default
            }

            return decoded
        }
        set {
            editorConfigurationData = try? JSONEncoder().encode(newValue)
        }
    }

    var editorFingerprint: String {
        editorConfigurationData?.base64EncodedString() ?? ""
    }
}

@Model
final class DisplayProfileRecord {
    @Attribute(.unique) var screenID: String
    var assignedAssetID: UUID?
    var layoutModeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        screenID: String,
        assignedAssetID: UUID?,
        layoutMode: WallpaperLayoutMode = .fill
    ) {
        self.screenID = screenID
        self.assignedAssetID = assignedAssetID
        self.layoutModeRawValue = layoutMode.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var layoutMode: WallpaperLayoutMode {
        get { WallpaperLayoutMode(rawValue: layoutModeRawValue) ?? .fill }
        set {
            layoutModeRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var id: String
    var pauseWhenCovered: Bool
    var pauseDuringFullscreenApps: Bool
    var reduceOnBattery: Bool
    var pauseWhenHot: Bool
    var coverageThreshold: Double
    var coveredDebounceSeconds: Double
    var fullscreenCoverageThreshold: Double
    var batteryFPSCap: Int
    var normalFPSCap: Int?
    var createdAt: Date
    var updatedAt: Date

    init(id: String = "default", policy: PlaybackPolicy = .default) {
        self.id = id
        self.pauseWhenCovered = policy.pauseWhenCovered
        self.pauseDuringFullscreenApps = policy.pauseDuringFullscreenApps
        self.reduceOnBattery = policy.reduceOnBattery
        self.pauseWhenHot = policy.pauseWhenHot
        self.coverageThreshold = policy.coverageThreshold
        self.coveredDebounceSeconds = policy.coveredDebounceSeconds
        self.fullscreenCoverageThreshold = policy.fullscreenCoverageThreshold
        self.batteryFPSCap = policy.batteryFPSCap
        self.normalFPSCap = policy.normalFPSCap
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var policy: PlaybackPolicy {
        get {
            PlaybackPolicy(
                pauseWhenCovered: pauseWhenCovered,
                pauseDuringFullscreenApps: pauseDuringFullscreenApps,
                reduceOnBattery: reduceOnBattery,
                pauseWhenHot: pauseWhenHot,
                coverageThreshold: coverageThreshold,
                coveredDebounceSeconds: coveredDebounceSeconds,
                fullscreenCoverageThreshold: fullscreenCoverageThreshold,
                batteryFPSCap: batteryFPSCap,
                normalFPSCap: normalFPSCap
            )
        }
        set {
            pauseWhenCovered = newValue.pauseWhenCovered
            pauseDuringFullscreenApps = newValue.pauseDuringFullscreenApps
            reduceOnBattery = newValue.reduceOnBattery
            pauseWhenHot = newValue.pauseWhenHot
            coverageThreshold = newValue.coverageThreshold
            coveredDebounceSeconds = newValue.coveredDebounceSeconds
            fullscreenCoverageThreshold = newValue.fullscreenCoverageThreshold
            batteryFPSCap = newValue.batteryFPSCap
            normalFPSCap = newValue.normalFPSCap
            updatedAt = Date()
        }
    }
}
