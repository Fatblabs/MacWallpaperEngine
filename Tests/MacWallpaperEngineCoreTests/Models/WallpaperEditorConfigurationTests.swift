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
        #expect(configuration.canvasResolution.mode == .autoNative)
    }

    @Test
    func canvasResolutionPresetsExposeTargetSizeAndScale() {
        let resolution = WallpaperCanvasResolution.fhd1080p

        #expect(resolution.pixelSize?.width == 1_920)
        #expect(resolution.pixelSize?.height == 1_080)
        #expect(resolution.backingScale(forDisplayPixelSize: (width: 3_840, height: 2_160)) == 0.5)
        #expect(resolution.aspectRatio(fallbackWidth: 1, fallbackHeight: 1) == 16.0 / 9.0)
    }

    @Test
    func customCanvasAspectIsClampedAndUsesFallbackOnlyForAuto() {
        let custom = WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 21, customAspectHeight: 9)
        let auto = WallpaperCanvasResolution.auto

        #expect(custom.pixelSize == nil)
        #expect(custom.aspectRatio(fallbackWidth: 4, fallbackHeight: 3) == 21.0 / 9.0)
        #expect(auto.aspectRatio(fallbackWidth: 4, fallbackHeight: 3) == 4.0 / 3.0)
    }

    @Test
    func smoothVideoExportPresetClampsToSupportedRefreshCeiling() {
        let preset = SmoothVideoExportPreset(title: "Experimental", targetFPS: 1_000)

        #expect(preset.normalizedTargetFPS == 500)
        #expect(preset.exportLabel == "500fps Native")
    }

    @Test
    func smoothVideoExportDimensionsPreserveAspectAndEvenPixelSize() {
        let preset = SmoothVideoExportPreset(title: "4K", targetFPS: 120, maximumLongEdge: 3_840)

        let dimensions = preset.outputDimensions(sourceWidth: 1_920, sourceHeight: 1_080)

        #expect(dimensions == SmoothVideoExportDimensions(width: 3_840, height: 2_160))
    }

    @Test
    func nativeSmoothVideoExportKeepsSourceSizeVideoEncoderFriendly() {
        let preset = SmoothVideoExportPreset(title: "Native", targetFPS: 120)

        let dimensions = preset.outputDimensions(sourceWidth: 1_279, sourceHeight: 719)

        #expect(dimensions == SmoothVideoExportDimensions(width: 1_280, height: 720))
    }

    @Test
    func customSmoothVideoExportUsesExactNormalizedDimensions() {
        let preset = SmoothVideoExportPreset(
            title: "Custom",
            targetFPS: 144,
            customDimensions: SmoothVideoExportDimensions(width: 2_333, height: 1_311)
        )

        let dimensions = preset.outputDimensions(sourceWidth: 1_920, sourceHeight: 1_080)

        #expect(dimensions == SmoothVideoExportDimensions(width: 2_334, height: 1_312))
        #expect(preset.exportLabel == "144fps 2334x1312")
    }

    @Test
    func customSmoothVideoExportClampsOversizedDimensions() {
        let preset = SmoothVideoExportPreset(
            title: "Too Big",
            targetFPS: 120,
            customDimensions: SmoothVideoExportDimensions(width: 99_999, height: 8_001)
        )

        let dimensions = preset.outputDimensions(sourceWidth: 1_920, sourceHeight: 1_080)

        #expect(dimensions == SmoothVideoExportDimensions(width: 7_680, height: 7_680))
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
        let bookmarkData = Data([1, 2, 3])
        let editorConfigurationData = try JSONEncoder().encode(WallpaperEditorConfiguration.default)
        let snapshot = PersistentWallpaperSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_234),
            activeAssetIDs: [assetID],
            assets: [
                WallpaperAssetRestoreMetadata(
                    id: assetID,
                    displayName: "Ocean",
                    originalFilename: "ocean.mov",
                    bookmarkData: bookmarkData,
                    lastKnownPath: "/Users/example/ocean.mov",
                    duration: 42,
                    pixelWidth: 3840,
                    pixelHeight: 2160,
                    codecSummary: "hvc1",
                    posterFrameFilename: "poster.png",
                    editorConfigurationData: editorConfigurationData,
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
        #expect(decoded.assets.first?.bookmarkData == bookmarkData)
        #expect(decoded.assets.first?.editorConfigurationData == editorConfigurationData)
        #expect(decoded.assets.first?.editorConfiguration == .default)
    }

    @Test
    func persistentWallpaperSnapshotDecodesLegacyMetadata() throws {
        let assetID = UUID()
        let snapshotJSON = """
        {
          "updatedAt": 1234,
          "activeAssetIDs": ["\(assetID.uuidString)"],
          "assets": [
            {
              "id": "\(assetID.uuidString)",
              "displayName": "Ocean",
              "originalFilename": "ocean.mov",
              "lastKnownPath": "/Users/example/ocean.mov",
              "duration": 42,
              "pixelWidth": 3840,
              "pixelHeight": 2160,
              "codecSummary": "hvc1",
              "posterFrameFilename": "poster.png",
              "editorFingerprint": "abc"
            }
          ],
          "displayAssignments": [
            {
              "screenID": "100",
              "assetID": "\(assetID.uuidString)",
              "layoutModeRawValue": "fill"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PersistentWallpaperSnapshot.self, from: snapshotJSON)

        #expect(decoded.assets.first?.bookmarkData == nil)
        #expect(decoded.assets.first?.editorConfigurationData == nil)
        #expect(decoded.assets.first?.editorConfiguration == .default)
    }
}
