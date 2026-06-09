import Foundation

public enum PowerSourceState: String, Codable, Equatable, Sendable {
    case ac
    case battery
    case unknown
}

public enum ThermalPressure: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public enum PauseReason: String, Codable, Equatable, Sendable {
    case manual
    case covered
    case fullscreen
    case lowPowerMode
    case thermal
    case screenSleep
}

public enum PlaybackMode: Codable, Equatable, Sendable {
    case full
    case capped(fps: Int)
    case posterFrame(reason: PauseReason)
    case paused(reason: PauseReason)
}

public struct PlaybackPolicy: Codable, Equatable, Sendable {
    public var pauseWhenCovered: Bool
    public var pauseDuringFullscreenApps: Bool
    public var reduceOnBattery: Bool
    public var pauseWhenHot: Bool
    public var coverageThreshold: Double
    public var coveredDebounceSeconds: TimeInterval
    public var fullscreenCoverageThreshold: Double
    public var batteryFPSCap: Int
    public var normalFPSCap: Int?

    public init(
        pauseWhenCovered: Bool = true,
        pauseDuringFullscreenApps: Bool = true,
        reduceOnBattery: Bool = true,
        pauseWhenHot: Bool = true,
        coverageThreshold: Double = 0.85,
        coveredDebounceSeconds: TimeInterval = 1.5,
        fullscreenCoverageThreshold: Double = 0.98,
        batteryFPSCap: Int = 15,
        normalFPSCap: Int? = nil
    ) {
        self.pauseWhenCovered = pauseWhenCovered
        self.pauseDuringFullscreenApps = pauseDuringFullscreenApps
        self.reduceOnBattery = reduceOnBattery
        self.pauseWhenHot = pauseWhenHot
        self.coverageThreshold = coverageThreshold
        self.coveredDebounceSeconds = coveredDebounceSeconds
        self.fullscreenCoverageThreshold = fullscreenCoverageThreshold
        self.batteryFPSCap = batteryFPSCap
        self.normalFPSCap = normalFPSCap
    }

    public static let `default` = PlaybackPolicy()
}

public struct PlaybackContext: Equatable, Sendable {
    public var displayID: UInt32
    public var desktopCoverage: Double
    public var isFullscreenAppCoveringDisplay: Bool
    public var powerSource: PowerSourceState
    public var isLowPowerModeEnabled: Bool
    public var thermalPressure: ThermalPressure
    public var isScreenSleeping: Bool
    public var isManuallyPaused: Bool
    public var now: Date

    public init(
        displayID: UInt32,
        desktopCoverage: Double,
        isFullscreenAppCoveringDisplay: Bool,
        powerSource: PowerSourceState,
        isLowPowerModeEnabled: Bool,
        thermalPressure: ThermalPressure,
        isScreenSleeping: Bool = false,
        isManuallyPaused: Bool = false,
        now: Date = Date()
    ) {
        self.displayID = displayID
        self.desktopCoverage = desktopCoverage
        self.isFullscreenAppCoveringDisplay = isFullscreenAppCoveringDisplay
        self.powerSource = powerSource
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalPressure = thermalPressure
        self.isScreenSleeping = isScreenSleeping
        self.isManuallyPaused = isManuallyPaused
        self.now = now
    }
}

public final class PlaybackPolicyEngine {
    private var coveredSinceByDisplay: [UInt32: Date] = [:]

    public init() {}

    public func reset() {
        coveredSinceByDisplay.removeAll()
    }

    public func mode(for context: PlaybackContext, policy: PlaybackPolicy) -> PlaybackMode {
        if context.isManuallyPaused {
            return .paused(reason: .manual)
        }

        if context.isScreenSleeping {
            return .paused(reason: .screenSleep)
        }

        if policy.pauseWhenHot {
            switch context.thermalPressure {
            case .serious, .critical:
                return .paused(reason: .thermal)
            case .nominal, .fair:
                break
            }
        }

        if context.isLowPowerModeEnabled {
            return .posterFrame(reason: .lowPowerMode)
        }

        if policy.pauseDuringFullscreenApps && context.isFullscreenAppCoveringDisplay {
            coveredSinceByDisplay[context.displayID] = nil
            return .paused(reason: .fullscreen)
        }

        if policy.pauseWhenCovered && context.desktopCoverage >= policy.coverageThreshold {
            let coveredSince = coveredSinceByDisplay[context.displayID] ?? context.now
            coveredSinceByDisplay[context.displayID] = coveredSince

            if context.now.timeIntervalSince(coveredSince) >= policy.coveredDebounceSeconds {
                return .paused(reason: .covered)
            }
        } else {
            coveredSinceByDisplay[context.displayID] = nil
        }

        if policy.reduceOnBattery && context.powerSource == .battery {
            return .capped(fps: max(1, policy.batteryFPSCap))
        }

        if let normalFPSCap = policy.normalFPSCap {
            return .capped(fps: max(1, normalFPSCap))
        }

        return .full
    }
}
