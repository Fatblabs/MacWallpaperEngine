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
    func frameRateCapsSupportFiveHundredHertz() {
        let engine = PlaybackPolicyEngine()
        let context = PlaybackContext(
            displayID: 1,
            desktopCoverage: 0,
            isFullscreenAppCoveringDisplay: false,
            powerSource: .ac,
            isLowPowerModeEnabled: false,
            thermalPressure: .nominal
        )
        let policy = PlaybackPolicy(normalFPSCap: 999)

        #expect(engine.mode(for: context, policy: policy) == .capped(fps: 500))
        #expect(PlaybackFrameRateCompensation.clampedTargetFPS(500) == 500)
        #expect(PlaybackFrameRateCompensation.clampedTargetFPS(501) == 500)
    }

    @Test
    func frameRateCompensationMatchesTargetToSourceRatio() {
        #expect(PlaybackFrameRateCompensation.multiplier(sourceFPS: 60, targetFPS: 120) == 2)
        #expect(PlaybackFrameRateCompensation.multiplier(sourceFPS: 120, targetFPS: 60) == 1)
        #expect(PlaybackFrameRateCompensation.multiplier(sourceFPS: 60, targetFPS: 500).rounded(.down) == 8)
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
