import Foundation

public enum WallpaperTextAlignment: String, CaseIterable, Codable, Equatable, Sendable {
    case left
    case center
    case right
}

public enum WallpaperOverlayPosition: String, CaseIterable, Codable, Equatable, Sendable {
    case topLeft
    case topRight
    case center
    case bottomLeft
    case bottomRight
}

public enum WallpaperThemeSyncMode: String, CaseIterable, Codable, Equatable, Sendable {
    case off
    case systemAppearance
    case timeOfDay
}

public enum WallpaperAppearance: String, Codable, Equatable, Sendable {
    case light
    case dark
}

public struct VideoTrimConfiguration: Codable, Equatable, Sendable {
    public static let longVideoThresholdSeconds: Double = 60

    public var startSeconds: Double
    public var endSeconds: Double?

    public init(startSeconds: Double = 0, endSeconds: Double? = nil) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public static func shouldShowTrimControls(duration: Double) -> Bool {
        duration >= longVideoThresholdSeconds
    }

    public func normalized(forDuration duration: Double) -> VideoTrimConfiguration {
        guard duration.isFinite, duration > 0 else {
            return VideoTrimConfiguration(startSeconds: 0, endSeconds: nil)
        }

        let start = min(max(0, startSeconds), max(0, duration - 0.5))
        let requestedEnd = endSeconds ?? duration
        let end = min(max(start + 0.5, requestedEnd), duration)
        return VideoTrimConfiguration(startSeconds: start, endSeconds: end)
    }

    public func effectiveEndSeconds(forDuration duration: Double) -> Double {
        normalized(forDuration: duration).endSeconds ?? max(0, duration)
    }
}

public struct ColorTuningConfiguration: Codable, Equatable, Sendable {
    public var hueDegrees: Double
    public var saturation: Double
    public var brightness: Double
    public var contrast: Double

    public init(
        hueDegrees: Double = 0,
        saturation: Double = 1,
        brightness: Double = 0,
        contrast: Double = 1
    ) {
        self.hueDegrees = hueDegrees
        self.saturation = saturation
        self.brightness = brightness
        self.contrast = contrast
    }
}

public struct BlurTintConfiguration: Codable, Equatable, Sendable {
    public var blurRadius: Double
    public var tintOpacity: Double

    public init(blurRadius: Double = 0, tintOpacity: Double = 0) {
        self.blurRadius = blurRadius
        self.tintOpacity = tintOpacity
    }
}

public struct ComponentLayerConfiguration: Codable, Equatable, Sendable {
    public var showVideo: Bool
    public var showAmbientFog: Bool
    public var showMovingClouds: Bool
    public var showForegroundVignette: Bool
    public var showCustomText: Bool
    public var showWidgets: Bool

    public init(
        showVideo: Bool = true,
        showAmbientFog: Bool = false,
        showMovingClouds: Bool = false,
        showForegroundVignette: Bool = false,
        showCustomText: Bool = true,
        showWidgets: Bool = true
    ) {
        self.showVideo = showVideo
        self.showAmbientFog = showAmbientFog
        self.showMovingClouds = showMovingClouds
        self.showForegroundVignette = showForegroundVignette
        self.showCustomText = showCustomText
        self.showWidgets = showWidgets
    }
}

public struct MouseInteractionConfiguration: Codable, Equatable, Sendable {
    public var particlesFollowMouse: Bool
    public var parallaxDepth: Bool
    public var clickReactions: Bool

    public init(
        particlesFollowMouse: Bool = false,
        parallaxDepth: Bool = false,
        clickReactions: Bool = false
    ) {
        self.particlesFollowMouse = particlesFollowMouse
        self.parallaxDepth = parallaxDepth
        self.clickReactions = clickReactions
    }

    public var isEnabled: Bool {
        particlesFollowMouse || parallaxDepth || clickReactions
    }
}

public struct CustomTextConfiguration: Codable, Equatable, Sendable {
    public var text: String
    public var fontName: String
    public var fontSize: Double
    public var alignment: WallpaperTextAlignment
    public var position: WallpaperOverlayPosition

    public init(
        text: String = "",
        fontName: String = "Helvetica Neue",
        fontSize: Double = 34,
        alignment: WallpaperTextAlignment = .center,
        position: WallpaperOverlayPosition = .bottomRight
    ) {
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.alignment = alignment
        self.position = position
    }
}

public struct ClockCalendarConfiguration: Codable, Equatable, Sendable {
    public var showClock: Bool
    public var showCalendar: Bool
    public var use24HourClock: Bool
    public var fontName: String
    public var fontSize: Double
    public var alignment: WallpaperTextAlignment
    public var position: WallpaperOverlayPosition

    public init(
        showClock: Bool = false,
        showCalendar: Bool = false,
        use24HourClock: Bool = false,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 28,
        alignment: WallpaperTextAlignment = .right,
        position: WallpaperOverlayPosition = .topRight
    ) {
        self.showClock = showClock
        self.showCalendar = showCalendar
        self.use24HourClock = use24HourClock
        self.fontName = fontName
        self.fontSize = fontSize
        self.alignment = alignment
        self.position = position
    }

    public var isEnabled: Bool {
        showClock || showCalendar
    }
}

public struct ThemeSyncConfiguration: Codable, Equatable, Sendable {
    public var mode: WallpaperThemeSyncMode
    public var lightAssetID: UUID?
    public var darkAssetID: UUID?
    public var dayAssetID: UUID?
    public var nightAssetID: UUID?
    public var dayStartMinutes: Int
    public var nightStartMinutes: Int

    public init(
        mode: WallpaperThemeSyncMode = .off,
        lightAssetID: UUID? = nil,
        darkAssetID: UUID? = nil,
        dayAssetID: UUID? = nil,
        nightAssetID: UUID? = nil,
        dayStartMinutes: Int = 8 * 60,
        nightStartMinutes: Int = 19 * 60
    ) {
        self.mode = mode
        self.lightAssetID = lightAssetID
        self.darkAssetID = darkAssetID
        self.dayAssetID = dayAssetID
        self.nightAssetID = nightAssetID
        self.dayStartMinutes = dayStartMinutes
        self.nightStartMinutes = nightStartMinutes
    }

    public func effectiveAssetID(
        defaultAssetID: UUID,
        appearance: WallpaperAppearance,
        minuteOfDay: Int
    ) -> UUID {
        switch mode {
        case .off:
            return defaultAssetID
        case .systemAppearance:
            switch appearance {
            case .light:
                return lightAssetID ?? defaultAssetID
            case .dark:
                return darkAssetID ?? defaultAssetID
            }
        case .timeOfDay:
            return isDaytime(minuteOfDay: minuteOfDay) ? (dayAssetID ?? defaultAssetID) : (nightAssetID ?? defaultAssetID)
        }
    }

    public func isDaytime(minuteOfDay: Int) -> Bool {
        let minute = ((minuteOfDay % 1_440) + 1_440) % 1_440
        let dayStart = ((dayStartMinutes % 1_440) + 1_440) % 1_440
        let nightStart = ((nightStartMinutes % 1_440) + 1_440) % 1_440

        if dayStart < nightStart {
            return minute >= dayStart && minute < nightStart
        }

        return minute >= dayStart || minute < nightStart
    }
}

public struct WallpaperEditorConfiguration: Codable, Equatable, Sendable {
    public var videoTrim: VideoTrimConfiguration
    public var color: ColorTuningConfiguration
    public var blurTint: BlurTintConfiguration
    public var layers: ComponentLayerConfiguration
    public var playbackSpeed: Double
    public var mouseInteraction: MouseInteractionConfiguration
    public var themeSync: ThemeSyncConfiguration
    public var customText: CustomTextConfiguration
    public var clockCalendar: ClockCalendarConfiguration

    public init(
        videoTrim: VideoTrimConfiguration = VideoTrimConfiguration(),
        color: ColorTuningConfiguration = ColorTuningConfiguration(),
        blurTint: BlurTintConfiguration = BlurTintConfiguration(),
        layers: ComponentLayerConfiguration = ComponentLayerConfiguration(),
        playbackSpeed: Double = 1,
        mouseInteraction: MouseInteractionConfiguration = MouseInteractionConfiguration(),
        themeSync: ThemeSyncConfiguration = ThemeSyncConfiguration(),
        customText: CustomTextConfiguration = CustomTextConfiguration(),
        clockCalendar: ClockCalendarConfiguration = ClockCalendarConfiguration()
    ) {
        self.videoTrim = videoTrim
        self.color = color
        self.blurTint = blurTint
        self.layers = layers
        self.playbackSpeed = playbackSpeed
        self.mouseInteraction = mouseInteraction
        self.themeSync = themeSync
        self.customText = customText
        self.clockCalendar = clockCalendar
    }

    public static let `default` = WallpaperEditorConfiguration()

    public var clampedPlaybackSpeed: Double {
        min(max(playbackSpeed, 0.25), 2)
    }
}
