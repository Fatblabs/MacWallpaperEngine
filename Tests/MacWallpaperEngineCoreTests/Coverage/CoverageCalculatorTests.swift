import CoreGraphics
@testable import MacWallpaperEngineCore
import Testing

@Suite("CoverageCalculator")
struct CoverageCalculatorTests {
    @Test
    func overlappingWindowsDoNotDoubleCountCoverage() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [
            WindowSnapshot(bounds: CGRect(x: 0, y: 0, width: 60, height: 100), layer: 0, ownerPID: 100),
            WindowSnapshot(bounds: CGRect(x: 40, y: 0, width: 60, height: 100), layer: 0, ownerPID: 101)
        ]

        #expect(CoverageCalculator.desktopCoverage(displayFrame: display, windows: windows) == 1)
    }

    @Test
    func ignoresNonNormalWindowLayersAndOwnWindows() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [
            WindowSnapshot(bounds: display, layer: 20, ownerPID: 100),
            WindowSnapshot(bounds: display, layer: 0, ownerPID: 200)
        ]

        #expect(CoverageCalculator.desktopCoverage(displayFrame: display, windows: windows, ignoringOwnerPIDs: [200]) == 0)
    }

    @Test
    func detectsFullscreenCover() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [
            WindowSnapshot(bounds: CGRect(x: 1, y: 1, width: 99, height: 99), layer: 0, ownerPID: 100)
        ]

        #expect(CoverageCalculator.hasFullscreenCover(displayFrame: display, windows: windows, threshold: 0.98))
    }
}
