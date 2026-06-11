import CoreGraphics
import Foundation

public struct WindowSnapshot: Equatable, Sendable {
    public var bounds: CGRect
    public var layer: Int
    public var ownerPID: Int32
    public var alpha: Double
    public var isOnScreen: Bool

    public init(
        bounds: CGRect,
        layer: Int,
        ownerPID: Int32,
        alpha: Double = 1,
        isOnScreen: Bool = true
    ) {
        self.bounds = bounds
        self.layer = layer
        self.ownerPID = ownerPID
        self.alpha = alpha
        self.isOnScreen = isOnScreen
    }
}

public enum CoverageCalculator {
    public static func desktopCoverage(
        displayFrame: CGRect,
        windows: [WindowSnapshot],
        ignoringOwnerPIDs ignoredPIDs: Set<Int32> = []
    ) -> Double {
        let visibleRects = windows.compactMap { window -> CGRect? in
            guard window.isOnScreen else { return nil }
            guard window.layer == 0 else { return nil }
            guard window.alpha > 0.01 else { return nil }
            guard !ignoredPIDs.contains(window.ownerPID) else { return nil }

            let intersection = displayFrame.intersection(window.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            return intersection
        }

        guard !visibleRects.isEmpty else { return 0 }

        let displayArea = max(0, displayFrame.width) * max(0, displayFrame.height)
        guard displayArea > 0 else { return 0 }

        return min(1, unionArea(of: visibleRects) / displayArea)
    }

    public static func hasFullscreenCover(
        displayFrame: CGRect,
        windows: [WindowSnapshot],
        ignoringOwnerPIDs ignoredPIDs: Set<Int32> = [],
        threshold: Double = 0.98
    ) -> Bool {
        windows.contains { window in
            guard window.isOnScreen else { return false }
            guard window.layer == 0 else { return false }
            guard window.alpha > 0.01 else { return false }
            guard !ignoredPIDs.contains(window.ownerPID) else { return false }

            let intersection = displayFrame.intersection(window.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return false }
            let displayArea = displayFrame.width * displayFrame.height
            guard displayArea > 0 else { return false }
            return (intersection.width * intersection.height) / displayArea >= threshold
        }
    }

    private static func unionArea(of rects: [CGRect]) -> Double {
        let xCoordinates = Array(Set(rects.flatMap { [$0.minX, $0.maxX] })).sorted()
        guard xCoordinates.count >= 2 else { return 0 }

        var totalArea: Double = 0

        for index in 0..<(xCoordinates.count - 1) {
            let minX = xCoordinates[index]
            let maxX = xCoordinates[index + 1]
            let width = maxX - minX
            guard width > 0 else { continue }

            let yIntervals = rects.compactMap { rect -> ClosedRange<CGFloat>? in
                guard rect.minX < maxX && rect.maxX > minX else { return nil }
                return rect.minY...rect.maxY
            }

            let yCoverage = mergedLength(of: yIntervals)
            totalArea += Double(width * yCoverage)
        }

        return totalArea
    }

    private static func mergedLength(of intervals: [ClosedRange<CGFloat>]) -> CGFloat {
        let sortedIntervals = intervals.sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sortedIntervals.first else { return 0 }

        var total: CGFloat = 0

        for interval in sortedIntervals.dropFirst() {
            if interval.lowerBound <= current.upperBound {
                current = current.lowerBound...max(current.upperBound, interval.upperBound)
            } else {
                total += current.upperBound - current.lowerBound
                current = interval
            }
        }

        total += current.upperBound - current.lowerBound
        return total
    }
}
