import Foundation
import IOKit.ps
import MacWallpaperEngineCore

@MainActor
final class PowerStateMonitor {
    var onChange: (() -> Void)?

    private(set) var powerSource: PowerSourceState = .unknown
    private(set) var isLowPowerModeEnabled: Bool = false
    private(set) var thermalPressure: ThermalPressure = .nominal

    func start() {
        refresh()

        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        _ = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        powerSource = Self.currentPowerSource()
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalPressure = Self.currentThermalPressure()
        onChange?()
    }

    private static func currentPowerSource() -> PowerSourceState {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let source = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String? else {
            return .unknown
        }

        if source == kIOPSBatteryPowerValue {
            return .battery
        }

        if source == kIOPSACPowerValue || source == kIOPSOffLineValue {
            return .ac
        }

        return .unknown
    }

    private static func currentThermalPressure() -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            .nominal
        case .fair:
            .fair
        case .serious:
            .serious
        case .critical:
            .critical
        @unknown default:
            .nominal
        }
    }
}
