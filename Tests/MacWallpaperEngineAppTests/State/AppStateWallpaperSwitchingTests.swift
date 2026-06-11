import Foundation
import MacWallpaperEngineCore
@testable import MacWallpaperEngineApp
import SwiftData
import Testing

@Suite("Wallpaper Switching")
@MainActor
struct AppStateWallpaperSwitchingTests {
    @Test
    func setAssetSwitchesAllDisplaysToSelectedWallpaper() throws {
        let displays = WallpaperDisplay.displays()
        guard !displays.isEmpty else { return }

        let container = try ModelContainer(
            for: WallpaperAssetRecord.self,
            DisplayProfileRecord.self,
            AppSettingsRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let firstURL = try writeTemporaryMovie(named: "red")
        let secondURL = try writeTemporaryMovie(named: "blue")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let firstAsset = WallpaperAssetRecord(asset: asset(displayName: "Red", url: firstURL))
        let secondAsset = WallpaperAssetRecord(asset: asset(displayName: "Blue", url: secondURL))
        context.insert(firstAsset)
        context.insert(secondAsset)
        try context.save()

        let appState = AppState()
        appState.setAsset(firstAsset, for: nil, modelContext: context)
        let initialProfiles = try context.fetch(FetchDescriptor<DisplayProfileRecord>())
        #expect(initialProfiles.count == displays.count)
        #expect(initialProfiles.allSatisfy { $0.assignedAssetID == firstAsset.id })

        appState.setAsset(secondAsset, for: nil, modelContext: context)
        let switchedProfiles = try context.fetch(FetchDescriptor<DisplayProfileRecord>())
        #expect(switchedProfiles.count == displays.count)
        #expect(switchedProfiles.allSatisfy { $0.assignedAssetID == secondAsset.id })
        #expect(appState.statusMessage == "Set Blue")
    }

    private func asset(displayName: String, url: URL) -> WallpaperAsset {
        WallpaperAsset(
            displayName: displayName,
            originalFilename: url.lastPathComponent,
            bookmarkData: Data(),
            duration: 1,
            pixelWidth: 16,
            pixelHeight: 16,
            codecSummary: "Test",
            lastKnownPath: url.path
        )
    }

    private func writeTemporaryMovie(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
        try Data([1, 2, 3, 4]).write(to: url)
        return url
    }
}
