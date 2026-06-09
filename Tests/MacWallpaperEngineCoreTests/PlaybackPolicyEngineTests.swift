import Foundation
@testable import MacWallpaperEngineCore
import Testing

@Suite("PlaybackPolicyEngine")
struct PlaybackPolicyEngineTests {
    @Test
    func batteryPowerCapsFrameRate() {
        let engine = PlaybackPolicyEngine()
        let context = PlaybackContext(
            displayID: 1,
            desktopCoverage: 0,
            isFullscreenAppCoveringDisplay: false,
            powerSource: .battery,
            isLowPowerModeEnabled: false,
            thermalPressure: .nominal
        )

        #expect(engine.mode(for: context, policy: .default) == .capped(fps: 15))
    }

    @Test
    func fullscreenPausesImmediately() {
        let engine = PlaybackPolicyEngine()
        let context = PlaybackContext(
            displayID: 1,
            desktopCoverage: 1,
            isFullscreenAppCoveringDisplay: true,
            powerSource: .ac,
            isLowPowerModeEnabled: false,
            thermalPressure: .nominal
        )

        #expect(engine.mode(for: context, policy: .default) == .paused(reason: .fullscreen))
    }

    @Test
    func coveredDesktopPausesAfterDebounce() {
        let engine = PlaybackPolicyEngine()
        let start = Date(timeIntervalSince1970: 100)
        let firstContext = PlaybackContext(
            displayID: 1,
            desktopCoverage: 0.9,
            isFullscreenAppCoveringDisplay: false,
            powerSource: .ac,
            isLowPowerModeEnabled: false,
            thermalPressure: .nominal,
            now: start
        )
        let secondContext = PlaybackContext(
            displayID: 1,
            desktopCoverage: 0.9,
            isFullscreenAppCoveringDisplay: false,
            powerSource: .ac,
            isLowPowerModeEnabled: false,
            thermalPressure: .nominal,
            now: start.addingTimeInterval(1.6)
        )

        #expect(engine.mode(for: firstContext, policy: .default) == .full)
        #expect(engine.mode(for: secondContext, policy: .default) == .paused(reason: .covered))
    }

    @Test
    func thermalPressurePauses() {
        let engine = PlaybackPolicyEngine()
        let context = PlaybackContext(
            displayID: 1,
            desktopCoverage: 0,
            isFullscreenAppCoveringDisplay: false,
            powerSource: .ac,
            isLowPowerModeEnabled: false,
            thermalPressure: .serious
        )

        #expect(engine.mode(for: context, policy: .default) == .paused(reason: .thermal))
    }
}
