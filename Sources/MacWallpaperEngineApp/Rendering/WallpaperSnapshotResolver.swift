import Foundation
import MacWallpaperEngineCore

@MainActor
enum WallpaperSnapshotResolver {
    static func configurations(
        from snapshot: PersistentWallpaperSnapshot,
        displays: [WallpaperDisplay],
        appearance: WallpaperAppearance,
        minuteOfDay: Int
    ) -> [WallpaperDisplayConfiguration] {
        let urlsByAssetID = resolvedURLsByAssetID(from: snapshot)
        guard !urlsByAssetID.isEmpty else { return [] }

        let assetsByID = Dictionary(uniqueKeysWithValues: snapshot.assets.map { ($0.id, $0) })
        let activeAssetIDs = snapshot.activeAssetIDs.filter { urlsByAssetID[$0] != nil }
        let fallbackAssetID = activeAssetIDs.first ?? snapshot.assets.first { urlsByAssetID[$0.id] != nil }?.id

        return displays.compactMap { display in
            let assignment = snapshot.displayAssignments.first { $0.screenID == display.idString }
            let assignedAssetID = assignment?.assetID.flatMap { urlsByAssetID[$0] == nil ? nil : $0 }
            guard let selectedAssetID = assignedAssetID ?? fallbackAssetID,
                  var selectedAsset = assetsByID[selectedAssetID],
                  let selectedURL = urlsByAssetID[selectedAssetID] else {
                return nil
            }

            let selectedConfiguration = selectedAsset.editorConfiguration
            let variantID = selectedConfiguration.themeSync.effectiveAssetID(
                defaultAssetID: selectedAsset.id,
                appearance: appearance,
                minuteOfDay: minuteOfDay
            )

            if let variantAsset = assetsByID[variantID],
               urlsByAssetID[variantID] != nil {
                selectedAsset = variantAsset
            }

            let editorConfiguration = selectedAsset.editorConfiguration
            let layoutMode = assignment
                .flatMap { WallpaperLayoutMode(rawValue: $0.layoutModeRawValue) }
                ?? .fill

            return WallpaperDisplayConfiguration(
                display: display,
                assetID: selectedAsset.id,
                fileURL: urlsByAssetID[selectedAsset.id] ?? selectedURL,
                assetDuration: selectedAsset.duration,
                layoutMode: layoutMode,
                editorConfiguration: editorConfiguration,
                playlistItems: playlistItems(
                    for: selectedAsset,
                    configuration: editorConfiguration,
                    assetsByID: assetsByID,
                    urlsByAssetID: urlsByAssetID
                )
            )
        }
    }

    private static func playlistItems(
        for asset: WallpaperAssetRestoreMetadata,
        configuration: WallpaperEditorConfiguration,
        assetsByID: [UUID: WallpaperAssetRestoreMetadata],
        urlsByAssetID: [UUID: URL]
    ) -> [WallpaperPlaylistItemConfiguration] {
        let orderedIDs = configuration.playlist.assetIDs.isEmpty ? [asset.id] : configuration.playlist.assetIDs
        return orderedIDs.compactMap { id in
            guard let playlistAsset = assetsByID[id],
                  let url = urlsByAssetID[id] else {
                return nil
            }

            return WallpaperPlaylistItemConfiguration(
                id: playlistAsset.id,
                url: url,
                duration: playlistAsset.duration
            )
        }
    }

    private static func resolvedURLsByAssetID(from snapshot: PersistentWallpaperSnapshot) -> [UUID: URL] {
        Dictionary(uniqueKeysWithValues: snapshot.assets.compactMap { asset in
            guard let url = resolvedURL(for: asset) else { return nil }
            return (asset.id, url)
        })
    }

    private static func resolvedURL(for asset: WallpaperAssetRestoreMetadata) -> URL? {
        if let bookmarkData = asset.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.isFileURL {
                return url
            }
        }

        let fallbackURL = URL(fileURLWithPath: asset.lastKnownPath)
        guard fallbackURL.isFileURL,
              FileManager.default.fileExists(atPath: fallbackURL.path) else {
            return nil
        }
        return fallbackURL
    }
}
