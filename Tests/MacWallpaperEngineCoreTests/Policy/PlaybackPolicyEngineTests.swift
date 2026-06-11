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
        #expect(PlaybackFrameRateCap.clampedTargetFPS(500) == 500)
        #expect(PlaybackFrameRateCap.clampedTargetFPS(501) == 500)
    }

    @Test
    func frameRateCapDoesNotUpscaleSourceFrameRate() {
        #expect(PlaybackFrameRateCap.effectiveMaximumFPS(sourceFPS: 60, playbackRate: 1, targetFPS: 120) == 60)
        #expect(PlaybackFrameRateCap.effectiveMaximumFPS(sourceFPS: 60, playbackRate: 2, targetFPS: 60) == 60)
        #expect(PlaybackFrameRateCap.effectiveMaximumFPS(sourceFPS: 60, playbackRate: 2, targetFPS: 500) == 120)
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
