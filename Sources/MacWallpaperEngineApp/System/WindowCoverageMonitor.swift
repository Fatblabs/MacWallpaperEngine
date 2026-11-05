import AppKit
import CoreGraphics
import MacWallpaperEngineCore

struct ScreenRuntimeState: Equatable {
    var displayID: UInt32
    var desktopCoverage: Double
    var isFullscreenCovered: Bool
}

@MainActor
final class WindowCoverageMonitor {
    var onUpdate: (([ScreenRuntimeState]) -> Void)?
    var fullscreenCoverageThreshold = 0.98

    private var timer: Timer?
    private let ignoredPID = Int32(ProcessInfo.processInfo.processIdentifier)

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        timer?.tolerance = 0.1
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let windows = currentWindowSnapshots()
        let ignoredPIDs: Set<Int32> = [ignoredPID]
        let states = WallpaperDisplay.displays().map { display in
            ScreenRuntimeState(
                displayID: display.id,
                desktopCoverage: CoverageCalculator.desktopCoverage(
                    displayFrame: CGDisplayBounds(display.id),
                    windows: windows,
                    ignoringOwnerPIDs: ignoredPIDs
                ),
                isFullscreenCovered: CoverageCalculator.hasFullscreenCover(
                    displayFrame: CGDisplayBounds(display.id),
                    windows: windows,
                    ignoringOwnerPIDs: ignoredPIDs,
                    threshold: fullscreenCoverageThreshold
                )
            )
        }

        onUpdate?(states)
    }

    private func currentWindowSnapshots() -> [WindowSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info in
            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else {
                return nil
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true

            return WindowSnapshot(
                bounds: bounds,
                layer: layer,
                ownerPID: ownerPID,
                alpha: alpha,
                isOnScreen: isOnScreen
            )
        }
    }
}
