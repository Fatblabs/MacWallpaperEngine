import Foundation

public enum SmoothVideoInterpolationMode: String, CaseIterable, Codable, Equatable, Sendable {
    case duplicate
    case blend
    case opticalFlow

    public var displayTitle: String {
        switch self {
        case .duplicate:
            "Frame Repeat"
        case .blend:
            "GPU Blended Frame Gen"
        case .opticalFlow:
            "GPU Motion Prediction"
        }
    }
}

public struct SmoothVideoExportDimensions: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct SmoothVideoExportPreset: Identifiable, Codable, Equatable, Sendable {
    public static let maximumOutputDimension = 7_680

    public var title: String
    public var targetFPS: Int
    public var maximumLongEdge: Int?
    public var customDimensions: SmoothVideoExportDimensions?
    public var interpolationMode: SmoothVideoInterpolationMode

    public init(
        title: String,
        targetFPS: Int,
        maximumLongEdge: Int? = nil,
        customDimensions: SmoothVideoExportDimensions? = nil,
        interpolationMode: SmoothVideoInterpolationMode = .blend
    ) {
        self.title = title
        self.targetFPS = targetFPS
        self.maximumLongEdge = maximumLongEdge
        self.customDimensions = customDimensions
        self.interpolationMode = interpolationMode
    }

    public var id: String {
        let customSize = customDimensions.map { "\($0.width)x\($0.height)" } ?? "none"
        return "\(normalizedTargetFPS)-\(maximumLongEdge ?? 0)-\(customSize)-\(interpolationMode.rawValue)"
    }

    public var normalizedTargetFPS: Int {
        PlaybackFrameRateCap.clampedTargetFPS(targetFPS)
    }

    public var exportLabel: String {
        let size = customDimensions
            .map { "\(normalizedDimension($0.width))x\(normalizedDimension($0.height))" }
            ?? maximumLongEdge.map { "\(normalizedDimension($0))px long edge" }
            ?? "Native"
        return "\(normalizedTargetFPS)fps \(size)"
    }

    public func outputDimensions(sourceWidth: Int, sourceHeight: Int) -> SmoothVideoExportDimensions {
        if let customDimensions {
            return SmoothVideoExportDimensions(
                width: Self.normalizedDimension(customDimensions.width),
                height: Self.normalizedDimension(customDimensions.height)
            )
        }

        let safeWidth = max(2, sourceWidth)
        let safeHeight = max(2, sourceHeight)
        let sourceLongEdge = max(safeWidth, safeHeight)
        let targetLongEdge = maximumLongEdge.map { normalizedDimension($0) } ?? min(sourceLongEdge, Self.maximumOutputDimension)
        let scale = Double(targetLongEdge) / Double(sourceLongEdge)
        let width = Self.normalizedDimension(Int((Double(safeWidth) * scale).rounded()))
        let height = Self.normalizedDimension(Int((Double(safeHeight) * scale).rounded()))
        return SmoothVideoExportDimensions(width: width, height: height)
    }

    private static func evenDimension(_ value: Int) -> Int {
        let clamped = max(2, value)
        return clamped.isMultiple(of: 2) ? clamped : clamped + 1
    }

    private static func normalizedDimension(_ value: Int) -> Int {
        min(maximumOutputDimension, evenDimension(value))
    }

    private func normalizedDimension(_ value: Int) -> Int {
        Self.normalizedDimension(value)
    }
}
