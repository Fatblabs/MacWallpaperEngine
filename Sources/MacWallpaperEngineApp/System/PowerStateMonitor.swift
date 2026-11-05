import Foundation
import IOKit.ps
import MacWallpaperEngineCore

@MainActor
final class PowerStateMonitor {
    var onChange: (() -> Void)?

    private(set) var powerSource: PowerSourceState = .unknown
    private(set) var isLowPowerModeEnabled: Bool = false
    private(set) var thermalPressure: ThermalPressure = .nominal
    private var observers: [NSObjectProtocol] = []
    private var powerSourceNotification: CFRunLoopSource?

    func start() {
        guard observers.isEmpty else { return }
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSourceNotification = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerStateMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.refresh() }
        }, context)?.takeRetainedValue()
        if let powerSourceNotification {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceNotification, .commonModes)
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })

        _ = ProcessInfo.processInfo.thermalState
        observers.append(NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let powerSourceNotification { CFRunLoopSourceInvalidate(powerSourceNotification) }
        powerSourceNotification = nil
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
