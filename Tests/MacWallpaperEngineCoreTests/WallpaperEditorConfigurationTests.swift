import Foundation
@testable import MacWallpaperEngineCore
import Testing

@Suite("WallpaperEditorConfiguration")
struct WallpaperEditorConfigurationTests {
    @Test
    func trimControlsAppearForLongVideos() {
        #expect(VideoTrimConfiguration.shouldShowTrimControls(duration: 59.9) == false)
        #expect(VideoTrimConfiguration.shouldShowTrimControls(duration: 60) == true)
    }

    @Test
    func trimRangeIsClampedToDurationWithMinimumLength() {
        let trim = VideoTrimConfiguration(startSeconds: -4, endSeconds: 999).normalized(forDuration: 120)

        #expect(trim.startSeconds == 0)
        #expect(trim.endSeconds == 120)

        let narrowTrim = VideoTrimConfiguration(startSeconds: 119.9, endSeconds: 119.95).normalized(forDuration: 120)
        #expect(narrowTrim.startSeconds == 119.5)
        #expect(narrowTrim.endSeconds == 120)
    }

    @Test
    func performanceSnippetCapsLongSelectionsToSixtySeconds() {
        let trim = VideoTrimConfiguration(startSeconds: 10, endSeconds: 110).performanceSnippet(forDuration: 180)

        #expect(trim.startSeconds == 10)
        #expect(trim.endSeconds == 70)
    }

    @Test
    func performanceSnippetExpandsTinySelectionsTowardThirtySecondsWhenPossible() {
        let trim = VideoTrimConfiguration(startSeconds: 15, endSeconds: 16).performanceSnippet(forDuration: 90)

        #expect(trim.startSeconds == 15)
        #expect(trim.endSeconds == 45)
    }

    @Test
    func lightDarkThemeSyncChoosesConfiguredVariant() {
        let defaultID = UUID()
        let lightID = UUID()
        let darkID = UUID()
        let sync = ThemeSyncConfiguration(
            mode: .systemAppearance,
            lightAssetID: lightID,
            darkAssetID: darkID
        )

        #expect(sync.effectiveAssetID(defaultAssetID: defaultID, appearance: .light, minuteOfDay: 12 * 60) == lightID)
        #expect(sync.effectiveAssetID(defaultAssetID: defaultID, appearance: .dark, minuteOfDay: 12 * 60) == darkID)
    }

    @Test
    func scheduleThemeSyncHandlesOvernightRanges() {
        let defaultID = UUID()
        let dayID = UUID()
        let nightID = UUID()
        let sync = ThemeSyncConfiguration(
            mode: .timeOfDay,
            dayAssetID: dayID,
            nightAssetID: nightID,
            dayStartMinutes: 7 * 60,
            nightStartMinutes: 19 * 60
        )

        #expect(sync.effectiveAssetID(defaultAssetID: defaultID, appearance: .light, minuteOfDay: 12 * 60) == dayID)
        #expect(sync.effectiveAssetID(defaultAssetID: defaultID, appearance: .light, minuteOfDay: 23 * 60) == nightID)

        let overnightDay = ThemeSyncConfiguration(
            mode: .timeOfDay,
            dayAssetID: dayID,
            nightAssetID: nightID,
            dayStartMinutes: 22 * 60,
            nightStartMinutes: 6 * 60
        )

        #expect(overnightDay.effectiveAssetID(defaultAssetID: defaultID, appearance: .light, minuteOfDay: 23 * 60) == dayID)
        #expect(overnightDay.effectiveAssetID(defaultAssetID: defaultID, appearance: .light, minuteOfDay: 12 * 60) == nightID)
    }

    @Test
    func playbackSpeedIsClampedForRendererSafety() {
        var configuration = WallpaperEditorConfiguration.default
        configuration.playbackSpeed = 10
        #expect(configuration.clampedPlaybackSpeed == 2)

        configuration.playbackSpeed = 0.01
        #expect(configuration.clampedPlaybackSpeed == 0.25)
    }

    @Test
    func playlistMovePreservesOrderAndClampsCurrentIndex() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var playlist = PlaylistConfiguration(assetIDs: [first, second, third], currentIndex: 5)

        playlist.move(from: IndexSet(integer: 0), to: 3)

        #expect(playlist.assetIDs == [second, third, first])
        #expect(playlist.currentIndex == 2)
    }

    @Test
    func invisibleOrEmptyWidgetsDoNotEmitVisibleContent() {
        var clock = DesktopWidgetConfiguration.clock()
        clock.clock.showTime = false
        clock.clock.showDate = false
        #expect(clock.emitsVisibleContent == false)

        clock.clock.showTime = true
        #expect(clock.emitsVisibleContent)

        clock.isVisible = false
        #expect(clock.emitsVisibleContent == false)
    }

    @Test
    func editorDecodesLegacyPayloadWithDefaultSchemaAdditions() throws {
        let legacyJSON = """
        {
          "playbackSpeed": 1.0
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(WallpaperEditorConfiguration.self, from: legacyJSON)

        #expect(configuration.playbackSpeed == 1)
        #expect(configuration.widgets.isEmpty)
        #expect(configuration.playlist.assetIDs.isEmpty)
    }

    @Test
    func removingWallpaperCleansPlaylistAndThemeReferences() {
        let removedID = UUID()
        let survivorID = UUID()
        var configuration = WallpaperEditorConfiguration.default
        configuration.playlist = PlaylistConfiguration(assetIDs: [removedID, survivorID], currentIndex: 4)
        configuration.themeSync = ThemeSyncConfiguration(
            mode: .systemAppearance,
            lightAssetID: removedID,
            darkAssetID: survivorID,
            dayAssetID: removedID,
            nightAssetID: survivorID
        )

        let cleaned = WallpaperReferenceCleanup.cleaned(configuration: configuration, removing: removedID)

        #expect(cleaned.playlist.assetIDs == [survivorID])
        #expect(cleaned.playlist.currentIndex == 0)
        #expect(cleaned.themeSync.lightAssetID == nil)
        #expect(cleaned.themeSync.darkAssetID == survivorID)
        #expect(cleaned.themeSync.dayAssetID == nil)
        #expect(cleaned.themeSync.nightAssetID == survivorID)
    }

    @Test
    func persistentWallpaperSnapshotRoundTripsDisplayAssignments() throws {
        let assetID = UUID()
        let snapshot = PersistentWallpaperSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_234),
            activeAssetIDs: [assetID],
            assets: [
                WallpaperAssetRestoreMetadata(
                    id: assetID,
                    displayName: "Ocean",
                    originalFilename: "ocean.mov",
                    lastKnownPath: "/Users/example/ocean.mov",
                    duration: 42,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    codecSummary: "hvc1",
                    posterFrameFilename: "poster.png",
                    editorFingerprint: "abc"
                )
            ],
            displayAssignments: [
                WallpaperDisplayAssignmentSnapshot(
                    screenID: "100",
                    assetID: assetID,
                    layoutModeRawValue: "fill"
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PersistentWallpaperSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.assignedAssetID(for: "100") == assetID)
        #expect(decoded.assignedAssetID(for: "missing") == nil)
    }
}
