import Foundation
import MacWallpaperEngineCore

enum WallpaperStateCache {
    private static let defaultsKey = "MacWallpaperEngine.persistentWallpaperSnapshot"

    static func load() -> PersistentWallpaperSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistentWallpaperSnapshot.self, from: data)
    }

    static func save(assets: [WallpaperAssetRecord], profiles: [DisplayProfileRecord]) {
        let snapshot = PersistentWallpaperSnapshot(
            activeAssetIDs: assets.map(\.id),
            assets: assets.map { asset in
                WallpaperAssetRestoreMetadata(
                    id: asset.id,
                    displayName: asset.displayName,
                    originalFilename: asset.originalFilename,
                    lastKnownPath: asset.lastKnownPath,
                    duration: asset.duration,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    codecSummary: asset.codecSummary,
                    posterFrameFilename: asset.posterFrameFilename,
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

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
