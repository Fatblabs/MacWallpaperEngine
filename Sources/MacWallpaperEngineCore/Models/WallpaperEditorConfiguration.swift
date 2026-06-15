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

public enum WallpaperCanvasResolutionMode: String, CaseIterable, Codable, Equatable, Sendable {
    case autoNative
    case fourK
    case qhd1440p
    case fhd1080p
    case customAspect
}

public struct WallpaperCanvasResolution: Codable, Equatable, Sendable {
    public var mode: WallpaperCanvasResolutionMode
    public var customAspectWidth: Double
    public var customAspectHeight: Double

    public init(
        mode: WallpaperCanvasResolutionMode = .autoNative,
        customAspectWidth: Double = 16,
        customAspectHeight: Double = 9
    ) {
        self.mode = mode
        self.customAspectWidth = customAspectWidth
        self.customAspectHeight = customAspectHeight
    }

    public static let auto = WallpaperCanvasResolution()
    public static let fourK = WallpaperCanvasResolution(mode: .fourK)
    public static let qhd1440p = WallpaperCanvasResolution(mode: .qhd1440p)
    public static let fhd1080p = WallpaperCanvasResolution(mode: .fhd1080p)

    public var displayTitle: String {
        switch mode {
        case .autoNative:
            "Auto / Native"
        case .fourK:
            "4K"
        case .qhd1440p:
            "1440p"
        case .fhd1080p:
            "1080p"
        case .customAspect:
            "Custom \(formatted(customAspectWidth)):\(formatted(customAspectHeight))"
        }
    }

    public var pixelSize: (width: Int, height: Int)? {
        switch mode {
        case .autoNative, .customAspect:
            nil
        case .fourK:
            (3_840, 2_160)
        case .qhd1440p:
            (2_560, 1_440)
        case .fhd1080p:
            (1_920, 1_080)
        }
    }

    public func aspectRatio(fallbackWidth: Double, fallbackHeight: Double) -> Double {
        switch mode {
        case .autoNative:
            guard fallbackWidth > 0, fallbackHeight > 0 else { return 16.0 / 9.0 }
            return fallbackWidth / fallbackHeight
        case .customAspect:
            return sanitizedAspectWidth / sanitizedAspectHeight
        case .fourK, .qhd1440p, .fhd1080p:
            return 16.0 / 9.0
        }
    }

    public func backingScale(forDisplayPixelSize displayPixelSize: (width: Double, height: Double)) -> Double? {
        guard let pixelSize else { return nil }
        guard displayPixelSize.width > 0, displayPixelSize.height > 0 else { return nil }
        return min(1, max(0.25, min(Double(pixelSize.width) / displayPixelSize.width, Double(pixelSize.height) / displayPixelSize.height)))
    }

    private var sanitizedAspectWidth: Double {
        min(max(customAspectWidth, 1), 64)
    }

    private var sanitizedAspectHeight: Double {
        min(max(customAspectHeight, 1), 64)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

public struct VideoTrimConfiguration: Codable, Equatable, Sendable {
    public static let longVideoThresholdSeconds: Double = 60
    public static let minimumOptimizedSnippetSeconds: Double = 30
    public static let maximumOptimizedSnippetSeconds: Double = 60

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

    public func performanceSnippet(forDuration duration: Double) -> VideoTrimConfiguration {
        guard duration.isFinite, duration > 0 else {
            return VideoTrimConfiguration(startSeconds: 0, endSeconds: nil)
        }

        let normalized = normalized(forDuration: duration)
        let requestedStart = normalized.startSeconds
        let requestedEnd = normalized.effectiveEndSeconds(forDuration: duration)
        let requestedLength = requestedEnd - requestedStart
        let targetLength = min(
            max(requestedLength, Self.minimumOptimizedSnippetSeconds),
            min(Self.maximumOptimizedSnippetSeconds, duration)
        )
        let start = min(requestedStart, max(0, duration - targetLength))
        return VideoTrimConfiguration(startSeconds: start, endSeconds: min(duration, start + targetLength))
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

public enum DesktopWidgetKind: String, CaseIterable, Codable, Equatable, Sendable {
    case clock
    case hardwareMonitor
    case weather
}

public enum WidgetAnchor: String, CaseIterable, Codable, Equatable, Sendable {
    case absolute
    case topLeft
    case topRight
    case center
    case bottomLeft
    case bottomRight
}

public enum HardwareGraphStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case compactText
    case bar
    case line
}

public struct WidgetLayoutConfiguration: Codable, Equatable, Sendable {
    public var anchor: WidgetAnchor
    public var x: Double
    public var y: Double
    public var isAnchorLocked: Bool

    public init(
        anchor: WidgetAnchor = .topRight,
        x: Double = 32,
        y: Double = 32,
        isAnchorLocked: Bool = true
    ) {
        self.anchor = anchor
        self.x = x
        self.y = y
        self.isAnchorLocked = isAnchorLocked
    }
}

public struct WidgetColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double = 1, green: Double = 1, blue: Double = 1, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = WidgetColor()
    public static let blackShadow = WidgetColor(red: 0, green: 0, blue: 0, alpha: 0.72)
}

public struct WidgetVisualStyle: Codable, Equatable, Sendable {
    public var fontName: String
    public var scale: Double
    public var opacity: Double
    public var foregroundColor: WidgetColor
    public var shadowColor: WidgetColor
    public var shadowRadius: Double

    public init(
        fontName: String = "Helvetica Neue",
        scale: Double = 1,
        opacity: Double = 1,
        foregroundColor: WidgetColor = .white,
        shadowColor: WidgetColor = .blackShadow,
        shadowRadius: Double = 8
    ) {
        self.fontName = fontName
        self.scale = scale
        self.opacity = opacity
        self.foregroundColor = foregroundColor
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
    }
}

public struct WidgetRefreshConfiguration: Codable, Equatable, Sendable {
    public var intervalSeconds: Double

    public init(intervalSeconds: Double = 1) {
        self.intervalSeconds = intervalSeconds
    }
}

public struct ClockWidgetProperties: Codable, Equatable, Sendable {
    public var showTime: Bool
    public var showDate: Bool
    public var use24HourClock: Bool
    public var alignment: WallpaperTextAlignment

    public init(
        showTime: Bool = true,
        showDate: Bool = false,
        use24HourClock: Bool = false,
        alignment: WallpaperTextAlignment = .right
    ) {
        self.showTime = showTime
        self.showDate = showDate
        self.use24HourClock = use24HourClock
        self.alignment = alignment
    }
}

public struct HardwareMonitorWidgetProperties: Codable, Equatable, Sendable {
    public var showCPU: Bool
    public var showRAM: Bool
    public var graphStyle: HardwareGraphStyle

    public init(showCPU: Bool = true, showRAM: Bool = true, graphStyle: HardwareGraphStyle = .compactText) {
        self.showCPU = showCPU
        self.showRAM = showRAM
        self.graphStyle = graphStyle
    }
}

public struct WeatherWidgetProperties: Codable, Equatable, Sendable {
    public var locationLabel: String
    public var useCelsius: Bool

    public init(locationLabel: String = "Local Weather", useCelsius: Bool = false) {
        self.locationLabel = locationLabel
        self.useCelsius = useCelsius
    }
}

public struct DesktopWidgetConfiguration: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: DesktopWidgetKind
    public var name: String
    public var isVisible: Bool
    public var layout: WidgetLayoutConfiguration
    public var style: WidgetVisualStyle
    public var refresh: WidgetRefreshConfiguration
    public var clock: ClockWidgetProperties
    public var hardwareMonitor: HardwareMonitorWidgetProperties
    public var weather: WeatherWidgetProperties

    public init(
        id: UUID = UUID(),
        kind: DesktopWidgetKind,
        name: String,
        isVisible: Bool = true,
        layout: WidgetLayoutConfiguration = WidgetLayoutConfiguration(),
        style: WidgetVisualStyle = WidgetVisualStyle(),
        refresh: WidgetRefreshConfiguration = WidgetRefreshConfiguration(),
        clock: ClockWidgetProperties = ClockWidgetProperties(),
        hardwareMonitor: HardwareMonitorWidgetProperties = HardwareMonitorWidgetProperties(),
        weather: WeatherWidgetProperties = WeatherWidgetProperties()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isVisible = isVisible
        self.layout = layout
        self.style = style
        self.refresh = refresh
        self.clock = clock
        self.hardwareMonitor = hardwareMonitor
        self.weather = weather
    }

    public static func clock(name: String = "Clock") -> DesktopWidgetConfiguration {
        DesktopWidgetConfiguration(kind: .clock, name: name, layout: WidgetLayoutConfiguration(anchor: .topRight))
    }

    public static func hardwareMonitor(name: String = "Hardware Monitor") -> DesktopWidgetConfiguration {
        DesktopWidgetConfiguration(
            kind: .hardwareMonitor,
            name: name,
            layout: WidgetLayoutConfiguration(anchor: .bottomRight),
            refresh: WidgetRefreshConfiguration(intervalSeconds: 2)
        )
    }

    public static func weather(name: String = "Weather") -> DesktopWidgetConfiguration {
        DesktopWidgetConfiguration(
            kind: .weather,
            name: name,
            layout: WidgetLayoutConfiguration(anchor: .topLeft),
            refresh: WidgetRefreshConfiguration(intervalSeconds: 1_800)
        )
    }

    public var emitsVisibleContent: Bool {
        guard isVisible else { return false }

        switch kind {
        case .clock:
            return clock.showTime || clock.showDate
        case .hardwareMonitor:
            return hardwareMonitor.showCPU || hardwareMonitor.showRAM
        case .weather:
            return !weather.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct PlaylistConfiguration: Codable, Equatable, Sendable {
    public var assetIDs: [UUID]
    public var currentIndex: Int
    public var crossfadeDuration: Double

    public init(assetIDs: [UUID] = [], currentIndex: Int = 0, crossfadeDuration: Double = 1.5) {
        self.assetIDs = assetIDs
        self.currentIndex = currentIndex
        self.crossfadeDuration = crossfadeDuration
    }

    public var isMultiVideo: Bool {
        assetIDs.count > 1
    }

    public func normalizedCurrentIndex() -> Int {
        guard !assetIDs.isEmpty else { return 0 }
        return min(max(0, currentIndex), assetIDs.count - 1)
    }

    public mutating func move(from source: IndexSet, to destination: Int) {
        let sourceIndexes = source.sorted()
        let moving = sourceIndexes.map { assetIDs[$0] }

        for index in sourceIndexes.reversed() {
            assetIDs.remove(at: index)
        }

        let removedBeforeDestination = sourceIndexes.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), assetIDs.count)
        assetIDs.insert(contentsOf: moving, at: insertionIndex)
        currentIndex = normalizedCurrentIndex()
    }

    public mutating func remove(_ assetID: UUID) {
        assetIDs.removeAll { $0 == assetID }
        if assetIDs.count <= 1 {
            resetToSingleVideo()
        } else {
            currentIndex = normalizedCurrentIndex()
        }
    }

    public mutating func resetToSingleVideo() {
        self = PlaylistConfiguration()
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
    public var canvasResolution: WallpaperCanvasResolution
    public var customText: CustomTextConfiguration
    public var clockCalendar: ClockCalendarConfiguration
    public var widgets: [DesktopWidgetConfiguration]
    public var playlist: PlaylistConfiguration

    public init(
        videoTrim: VideoTrimConfiguration = VideoTrimConfiguration(),
        color: ColorTuningConfiguration = ColorTuningConfiguration(),
        blurTint: BlurTintConfiguration = BlurTintConfiguration(),
        layers: ComponentLayerConfiguration = ComponentLayerConfiguration(),
        playbackSpeed: Double = 1,
        mouseInteraction: MouseInteractionConfiguration = MouseInteractionConfiguration(),
        themeSync: ThemeSyncConfiguration = ThemeSyncConfiguration(),
        canvasResolution: WallpaperCanvasResolution = WallpaperCanvasResolution(),
        customText: CustomTextConfiguration = CustomTextConfiguration(),
        clockCalendar: ClockCalendarConfiguration = ClockCalendarConfiguration(),
        widgets: [DesktopWidgetConfiguration] = [],
        playlist: PlaylistConfiguration = PlaylistConfiguration()
    ) {
        self.videoTrim = videoTrim
        self.color = color
        self.blurTint = blurTint
        self.layers = layers
        self.playbackSpeed = playbackSpeed
        self.mouseInteraction = mouseInteraction
        self.themeSync = themeSync
        self.canvasResolution = canvasResolution
        self.customText = customText
        self.clockCalendar = clockCalendar
        self.widgets = widgets
        self.playlist = playlist
    }

    public static let `default` = WallpaperEditorConfiguration()

    public var clampedPlaybackSpeed: Double {
        min(max(playbackSpeed, 0.25), 2)
    }

    public var activeWidgets: [DesktopWidgetConfiguration] {
        widgets.filter(\.emitsVisibleContent)
    }

    enum CodingKeys: String, CodingKey {
        case videoTrim
        case color
        case blurTint
        case layers
        case playbackSpeed
        case mouseInteraction
        case themeSync
        case canvasResolution
        case customText
        case clockCalendar
        case widgets
        case playlist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoTrim = try container.decodeIfPresent(VideoTrimConfiguration.self, forKey: .videoTrim) ?? VideoTrimConfiguration()
        color = try container.decodeIfPresent(ColorTuningConfiguration.self, forKey: .color) ?? ColorTuningConfiguration()
        blurTint = try container.decodeIfPresent(BlurTintConfiguration.self, forKey: .blurTint) ?? BlurTintConfiguration()
        layers = try container.decodeIfPresent(ComponentLayerConfiguration.self, forKey: .layers) ?? ComponentLayerConfiguration()
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1
        mouseInteraction = try container.decodeIfPresent(MouseInteractionConfiguration.self, forKey: .mouseInteraction) ?? MouseInteractionConfiguration()
        themeSync = try container.decodeIfPresent(ThemeSyncConfiguration.self, forKey: .themeSync) ?? ThemeSyncConfiguration()
        canvasResolution = try container.decodeIfPresent(WallpaperCanvasResolution.self, forKey: .canvasResolution) ?? WallpaperCanvasResolution()
        customText = try container.decodeIfPresent(CustomTextConfiguration.self, forKey: .customText) ?? CustomTextConfiguration()
        clockCalendar = try container.decodeIfPresent(ClockCalendarConfiguration.self, forKey: .clockCalendar) ?? ClockCalendarConfiguration()
        widgets = try container.decodeIfPresent([DesktopWidgetConfiguration].self, forKey: .widgets) ?? []
        playlist = try container.decodeIfPresent(PlaylistConfiguration.self, forKey: .playlist) ?? PlaylistConfiguration()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videoTrim, forKey: .videoTrim)
        try container.encode(color, forKey: .color)
        try container.encode(blurTint, forKey: .blurTint)
        try container.encode(layers, forKey: .layers)
        try container.encode(playbackSpeed, forKey: .playbackSpeed)
        try container.encode(mouseInteraction, forKey: .mouseInteraction)
        try container.encode(themeSync, forKey: .themeSync)
        try container.encode(canvasResolution, forKey: .canvasResolution)
        try container.encode(customText, forKey: .customText)
        try container.encode(clockCalendar, forKey: .clockCalendar)
        try container.encode(widgets, forKey: .widgets)
        try container.encode(playlist, forKey: .playlist)
    }
}
