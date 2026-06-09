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
}
