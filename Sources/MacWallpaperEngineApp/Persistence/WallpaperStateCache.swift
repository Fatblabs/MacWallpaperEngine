import Foundation
import MacWallpaperEngineCore

@MainActor
enum WallpaperStateCache {
    private static let defaultsKey = "MacWallpaperEngine.persistentWallpaperSnapshot"
    private static let filename = "WallpaperStateSnapshot.json"

    static func load() -> PersistentWallpaperSnapshot? {
        if let data = try? Data(contentsOf: snapshotFileURL()),
           let snapshot = try? JSONDecoder().decode(PersistentWallpaperSnapshot.self, from: data) {
            return snapshot
        }

        guard let data = AppStorage.defaults.data(forKey: defaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistentWallpaperSnapshot.self, from: data)
    }

    @discardableResult
    static func save(assets: [WallpaperAssetRecord], profiles: [DisplayProfileRecord]) -> PersistentWallpaperSnapshot? {
        let snapshot = PersistentWallpaperSnapshot(
            activeAssetIDs: assets.map(\.id),
            assets: assets.map { asset in
                WallpaperAssetRestoreMetadata(
                    id: asset.id,
                    displayName: asset.displayName,
                    originalFilename: asset.originalFilename,
                    bookmarkData: asset.bookmarkData,
                    lastKnownPath: asset.lastKnownPath,
                    duration: asset.duration,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    codecSummary: asset.codecSummary,
                    posterFrameFilename: asset.posterFrameFilename,
                    editorConfigurationData: asset.editorConfigurationData,
                    editorFingerprint: asset.editorFingerprint
                )
            },
            displayAssignments: profiles.map { profile in
                WallpaperDisplayAssignmentSnapshot(
                    screenID: profile.screenID,
                    assetID: profile.assignedAssetID,
                    layoutModeRawValue: profile.layoutModeRawValue
                )
            }
        )

        if let previous = load(), previous.activeAssetIDs == snapshot.activeAssetIDs,
           previous.assets == snapshot.assets, previous.displayAssignments == snapshot.displayAssignments {
            return previous
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot) else {
            return nil
        }

        if AppStorage.defaults.data(forKey: defaultsKey) != data {
            AppStorage.defaults.set(data, forKey: defaultsKey)
            saveToFile(data)
        }
        return snapshot
    }

    static func clear() {
        AppStorage.defaults.removeObject(forKey: defaultsKey)
        try? FileManager.default.removeItem(at: snapshotFileURL())
    }

    private static func saveToFile(_ data: Data) {
        let url = snapshotFileURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            AppStorage.defaults.set(data, forKey: defaultsKey)
        }
    }

    private static func snapshotFileURL() -> URL {
        AppStorage.root.appendingPathComponent(filename)
    }
}
