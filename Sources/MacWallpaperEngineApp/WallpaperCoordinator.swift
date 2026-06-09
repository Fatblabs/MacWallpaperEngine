import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import IOKit.ps
import MacWallpaperEngineCore
import os

@MainActor
final class WallpaperCoordinator {
    private var controllers: [UInt32: WallpaperWindowController] = [:]
    private let logger = Logger(subsystem: "MacWallpaperEngine", category: "WallpaperCoordinator")

    var activeDisplayIDs: [UInt32] {
        Array(controllers.keys)
    }

    func prepareForImmediateDisplay() {
        start()
        for controller in controllers.values {
            controller.prepareForImmediateDisplay()
        }
    }

    func start() {
        let displays = WallpaperDisplay.displays()
        let currentIDs = Set(displays.map(\.id))

        for id in controllers.keys where !currentIDs.contains(id) {
            controllers[id]?.close()
            controllers[id] = nil
        }

        for display in displays where controllers[display.id] == nil {
            controllers[display.id] = WallpaperWindowController(display: display)
        }
    }

    func apply(configurations: [WallpaperDisplayConfiguration]) {
        start()

        for configuration in configurations {
            let controller = controllers[configuration.display.id] ?? WallpaperWindowController(display: configuration.display)
            controllers[configuration.display.id] = controller
            controller.update(display: configuration.display)
            controller.setVideo(
                url: configuration.fileURL,
                assetDuration: configuration.assetDuration,
                playlistItems: configuration.playlistItems,
                layoutMode: configuration.layoutMode,
                editorConfiguration: configuration.editorConfiguration
            )
        }
    }

    func apply(_ mode: PlaybackMode, to displayID: UInt32) {
        guard let controller = controllers[displayID] else { return }
        controller.apply(mode)
    }

    func setEditMode(_ isEnabled: Bool) {
        for controller in controllers.values {
            controller.setEditMode(isEnabled)
        }
    }

    func setWidgetConfiguration(_ configuration: WidgetOverlayConfiguration) {
        for controller in controllers.values {
            controller.setWidgetConfiguration(configuration)
        }
    }
}

@MainActor
private final class WallpaperWindowController {
    private var display: WallpaperDisplay
    private let window: NSWindow
    private let videoView = VideoWallpaperView()
    private var activeURL: URL?
    private var activeDuration: Double = 0
    private var activePlaylistItems: [WallpaperPlaylistItemConfiguration] = []
    private var activeLayoutMode: WallpaperLayoutMode = .fill
    private var activeEditorConfiguration: WallpaperEditorConfiguration = .default

    init(display: WallpaperDisplay) {
        self.display = display
        self.window = NSWindow(
            contentRect: display.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: display.screen
        )

        configureWindow()
        window.contentView = videoView
        window.orderBack(nil)
    }

    func close() {
        videoView.prepareForClose()
        videoView.setVideo(
            url: nil,
            assetDuration: 0,
            playlistItems: [],
            layoutMode: .fill,
            editorConfiguration: .default
        )
        window.close()
    }

    func prepareForImmediateDisplay() {
        window.orderBack(nil)
        videoView.prepareForImmediateDisplay()
    }

    func update(display: WallpaperDisplay) {
        self.display = display
        window.setFrame(display.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderBack(nil)
    }

    func setVideo(
        url: URL?,
        assetDuration: Double,
        playlistItems: [WallpaperPlaylistItemConfiguration],
        layoutMode: WallpaperLayoutMode,
        editorConfiguration: WallpaperEditorConfiguration
    ) {
        guard activeURL != url ||
                activeDuration != assetDuration ||
                activePlaylistItems != playlistItems ||
                activeLayoutMode != layoutMode ||
                activeEditorConfiguration != editorConfiguration else {
            return
        }
        activeURL = url
        activeDuration = assetDuration
        activePlaylistItems = playlistItems
        activeLayoutMode = layoutMode
        activeEditorConfiguration = editorConfiguration
        videoView.setVideo(
            url: url,
            assetDuration: assetDuration,
            playlistItems: playlistItems,
            layoutMode: layoutMode,
            editorConfiguration: editorConfiguration
        )
        window.orderBack(nil)
    }

    func apply(_ mode: PlaybackMode) {
        videoView.apply(mode)
    }

    func setEditMode(_ isEnabled: Bool) {
        window.ignoresMouseEvents = !isEnabled
        videoView.setEditMode(isEnabled)
    }

    func setWidgetConfiguration(_ configuration: WidgetOverlayConfiguration) {
        videoView.setWidgetConfiguration(configuration)
    }

    private func configureWindow() {
        window.title = "MacWallpaperEngine \(display.name)"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.canHide = false
        window.ignoresMouseEvents = true
    }
}

@MainActor
private final class VideoWallpaperView: NSView {
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playlistItems: [WallpaperPlaylistItemConfiguration] = []
    private var playlistScopedURLs: [URL] = []
    private var playlistEndObserver: NSObjectProtocol?
    private var currentPlaylistIndex = 0
    private var playerLayer: AVPlayerLayer?
    private var placeholderLayer = CATextLayer()
    private var widgetLayer = CATextLayer()
    private let widgetRuntime = WidgetRuntimeHost()
    private var tintLayer = CALayer()
    private var fogLayer = CAGradientLayer()
    private var cloudLayer = CALayer()
    private var foregroundLayer = CAGradientLayer()
    private var customTextLayer = CATextLayer()
    private var cursorLayer = CALayer()
    private var clickPulseLayer = CALayer()
    private var widgetTimer: Timer?
    private var interactionTimer: Timer?
    private var clickEventMonitor: Any?
    private var widgetConfiguration = WidgetOverlayConfiguration()
    private var editorConfiguration = WallpaperEditorConfiguration.default
    private var lastPlaybackMode: PlaybackMode = .full
    private var securityScopedURL: URL?
    private var securityScopeIsActive = false

    private(set) var layoutMode: WallpaperLayoutMode = .fill

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configurePlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configurePlaceholder()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        placeholderLayer.frame = bounds.insetBy(dx: 40, dy: 40)
        tintLayer.frame = bounds
        fogLayer.frame = bounds
        cloudLayer.frame = bounds
        foregroundLayer.frame = bounds
        updateCustomTextFrame()
        updateDataDrivenWidgetFrames()
        updateWidgetFrame()
    }

    func prepareForImmediateDisplay() {
        layer?.backgroundColor = NSColor.black.cgColor
        showPlaceholder(playerLayer == nil)
    }

    func setVideo(
        url: URL?,
        assetDuration: Double,
        playlistItems: [WallpaperPlaylistItemConfiguration],
        layoutMode: WallpaperLayoutMode,
        editorConfiguration: WallpaperEditorConfiguration
    ) {
        stopSecurityScope()
        removePlaylistObserver()
        self.layoutMode = layoutMode
        self.editorConfiguration = editorConfiguration
        self.playlistItems = playlistItems

        guard let url else {
            queuePlayer?.pause()
            queuePlayer = nil
            looper = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil
            placeholderLayer.string = "Drop a local video to start"
            showPlaceholder(true)
            updateEditorPresentation()
            return
        }

        let playablePlaylistItems = playlistItems.filter { $0.url.isFileURL }
        if playablePlaylistItems.count > 1 {
            setPlaylist(
                playablePlaylistItems,
                fallbackURL: url,
                layoutMode: layoutMode,
                editorConfiguration: editorConfiguration
            )
            return
        }

        securityScopedURL = url
        securityScopeIsActive = url.startAccessingSecurityScopedResource()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let looper: AVPlayerLooper
        if assetDuration > 0 {
            let trim = editorConfiguration.videoTrim.normalized(forDuration: assetDuration)
            let start = CMTime(seconds: trim.startSeconds, preferredTimescale: 600)
            let end = CMTime(seconds: trim.effectiveEndSeconds(forDuration: assetDuration), preferredTimescale: 600)
            let timeRange = CMTimeRange(start: start, end: end)
            looper = AVPlayerLooper(player: player, templateItem: item, timeRange: timeRange)
        } else {
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = layoutMode.videoGravity
        layer.frame = bounds
        layer.backgroundColor = NSColor.black.cgColor

        playerLayer?.removeFromSuperlayer()
        self.queuePlayer = player
        self.looper = looper
        self.playerLayer = layer
        self.layer?.insertSublayer(layer, at: 0)
        showPlaceholder(false)
        updateEditorPresentation()
        fadeInPlayerLayer(layer)
        player.playImmediately(atRate: Float(editorConfiguration.clampedPlaybackSpeed))
    }

    private func setPlaylist(
        _ items: [WallpaperPlaylistItemConfiguration],
        fallbackURL: URL,
        layoutMode: WallpaperLayoutMode,
        editorConfiguration: WallpaperEditorConfiguration
    ) {
        playlistScopedURLs = []
        for item in items where item.url.startAccessingSecurityScopedResource() {
            playlistScopedURLs.append(item.url)
        }
        securityScopedURL = fallbackURL
        securityScopeIsActive = false

        currentPlaylistIndex = min(max(0, editorConfiguration.playlist.currentIndex), items.count - 1)

        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = layoutMode.videoGravity
        layer.frame = bounds
        layer.backgroundColor = NSColor.black.cgColor

        playerLayer?.removeFromSuperlayer()
        queuePlayer = player
        looper = nil
        playerLayer = layer
        self.layer?.insertSublayer(layer, at: 0)

        enqueuePlaylistItems(startingAt: currentPlaylistIndex, minimumQueuedItems: min(3, items.count))
        observePlaylistAdvancement()
        showPlaceholder(false)
        updateEditorPresentation()
        fadeInPlayerLayer(layer)
        player.playImmediately(atRate: Float(editorConfiguration.clampedPlaybackSpeed))
    }

    func apply(_ mode: PlaybackMode) {
        switch mode {
        case .full:
            queuePlayer?.playImmediately(atRate: Float(editorConfiguration.clampedPlaybackSpeed))
        case .capped:
            // AVPlayerLayer keeps decode/display in the native pipeline; the Metal path will enforce
            // true frame caps when enhanced rendering is enabled.
            queuePlayer?.playImmediately(atRate: Float(editorConfiguration.clampedPlaybackSpeed))
        case .posterFrame, .paused:
            queuePlayer?.pause()
        }
        lastPlaybackMode = mode
    }

    func setEditMode(_ isEnabled: Bool) {
        placeholderLayer.isHidden = !isEnabled && playerLayer != nil
        if isEnabled {
            placeholderLayer.string = "Edit Wallpaper Mode\nDrag widgets and layers here in the editor."
        } else if playerLayer == nil {
            placeholderLayer.string = "Drop a local video to start"
        }
    }

    func setWidgetConfiguration(_ configuration: WidgetOverlayConfiguration) {
        widgetConfiguration = configuration
        widgetLayer.isHidden = !configuration.isEnabled
        updateWidgetFrame()
        updateWidgetText()

        widgetTimer?.invalidate()
        widgetTimer = nil
        updateWidgetTimer()
    }

    func setEditorConfiguration(_ configuration: WallpaperEditorConfiguration) {
        editorConfiguration = configuration
        updateEditorPresentation()
        apply(lastPlaybackMode)
    }

    func prepareForClose() {
        widgetTimer?.invalidate()
        widgetTimer = nil
        interactionTimer?.invalidate()
        interactionTimer = nil
        if let clickEventMonitor {
            NSEvent.removeMonitor(clickEventMonitor)
            self.clickEventMonitor = nil
        }
        removePlaylistObserver()
        clearDataDrivenWidgetLayers()
        stopSecurityScope()
    }

    private func configurePlaceholder() {
        placeholderLayer.alignmentMode = .center
        placeholderLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
        placeholderLayer.fontSize = 24
        placeholderLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        placeholderLayer.string = "Drop a local video to start"
        placeholderLayer.frame = bounds.insetBy(dx: 40, dy: 40)
        layer?.addSublayer(placeholderLayer)

        tintLayer.frame = bounds
        tintLayer.backgroundColor = NSColor.black.cgColor
        tintLayer.opacity = 0
        layer?.addSublayer(tintLayer)

        fogLayer.frame = bounds
        fogLayer.colors = [
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor
        ]
        fogLayer.startPoint = CGPoint(x: 0, y: 0)
        fogLayer.endPoint = CGPoint(x: 1, y: 1)
        fogLayer.isHidden = true
        layer?.addSublayer(fogLayer)

        cloudLayer.frame = bounds
        cloudLayer.isHidden = true
        configureCloudLayer()
        layer?.addSublayer(cloudLayer)

        foregroundLayer.frame = bounds
        foregroundLayer.colors = [
            NSColor.black.withAlphaComponent(0.32).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.32).cgColor
        ]
        foregroundLayer.locations = [0, 0.5, 1]
        foregroundLayer.startPoint = CGPoint(x: 0, y: 0)
        foregroundLayer.endPoint = CGPoint(x: 1, y: 1)
        foregroundLayer.isHidden = true
        layer?.addSublayer(foregroundLayer)

        customTextLayer.foregroundColor = NSColor.white.cgColor
        customTextLayer.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        customTextLayer.cornerRadius = 8
        customTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        customTextLayer.isHidden = true
        layer?.addSublayer(customTextLayer)

        widgetLayer.alignmentMode = .right
        widgetLayer.foregroundColor = NSColor.white.cgColor
        widgetLayer.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        widgetLayer.cornerRadius = 8
        widgetLayer.fontSize = 22
        widgetLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        widgetLayer.isHidden = true
        layer?.addSublayer(widgetLayer)

        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        cursorLayer.cornerRadius = 14
        cursorLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.55).cgColor
        cursorLayer.shadowColor = NSColor.systemBlue.cgColor
        cursorLayer.shadowRadius = 18
        cursorLayer.shadowOpacity = 0.75
        cursorLayer.isHidden = true
        layer?.addSublayer(cursorLayer)

        clickPulseLayer.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        clickPulseLayer.cornerRadius = 48
        clickPulseLayer.borderWidth = 2
        clickPulseLayer.borderColor = NSColor.white.withAlphaComponent(0.75).cgColor
        clickPulseLayer.opacity = 0
        layer?.addSublayer(clickPulseLayer)
    }

    private func showPlaceholder(_ isShown: Bool) {
        placeholderLayer.isHidden = !isShown
        if isShown, placeholderLayer.superlayer == nil {
            layer?.addSublayer(placeholderLayer)
        }
    }

    private func stopSecurityScope() {
        if securityScopeIsActive, let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        for url in playlistScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        playlistScopedURLs = []
        securityScopedURL = nil
        securityScopeIsActive = false
    }

    private func enqueuePlaylistItems(startingAt startIndex: Int, minimumQueuedItems: Int) {
        guard let queuePlayer, !playlistItems.isEmpty else { return }

        var queuedCount = queuePlayer.items().count
        var nextIndex = (startIndex + queuedCount) % playlistItems.count

        while queuedCount < minimumQueuedItems {
            let current = playlistItems[nextIndex]
            let following = playlistItems[(nextIndex + 1) % playlistItems.count]
            let item = PlaylistCompositionFactory.playerItem(
                currentURL: current.url,
                nextURL: playlistItems.count > 1 ? following.url : nil,
                crossfadeDuration: editorConfiguration.playlist.crossfadeDuration
            )
            queuePlayer.insert(item, after: nil)
            queuedCount += 1
            nextIndex = (nextIndex + 1) % playlistItems.count
        }
    }

    private func observePlaylistAdvancement() {
        removePlaylistObserver()
        playlistEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isPlayerItemNotification = notification.object is AVPlayerItem
            Task { @MainActor in
                guard let self,
                      isPlayerItemNotification,
                      self.playlistItems.count > 1 else {
                    return
                }

                self.currentPlaylistIndex = (self.currentPlaylistIndex + 1) % max(1, self.playlistItems.count)
                self.enqueuePlaylistItems(startingAt: self.currentPlaylistIndex, minimumQueuedItems: min(3, self.playlistItems.count))
            }
        }
    }

    private func removePlaylistObserver() {
        if let playlistEndObserver {
            NotificationCenter.default.removeObserver(playlistEndObserver)
            self.playlistEndObserver = nil
        }
    }

    private func updateWidgetFrame() {
        guard editorConfiguration.activeWidgets.isEmpty else { return }
        let activeClock = editorConfiguration.layers.showWidgets && editorConfiguration.clockCalendar.isEnabled
        let size = CGSize(width: 300, height: activeClock && editorConfiguration.clockCalendar.showClock && editorConfiguration.clockCalendar.showCalendar ? 108 : 74)
        let inset: CGFloat = 32
        let origin: CGPoint

        let position = activeClock ? editorConfiguration.clockCalendar.position : legacyWidgetPosition()
        switch position {
        case .topLeft:
            origin = CGPoint(x: inset, y: bounds.height - size.height - inset)
            widgetLayer.alignmentMode = .left
        case .topRight:
            origin = CGPoint(x: bounds.width - size.width - inset, y: bounds.height - size.height - inset)
            widgetLayer.alignmentMode = .right
        case .center:
            origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            widgetLayer.alignmentMode = .center
        case .bottomLeft:
            origin = CGPoint(x: inset, y: inset)
            widgetLayer.alignmentMode = .left
        case .bottomRight:
            origin = CGPoint(x: bounds.width - size.width - inset, y: inset)
            widgetLayer.alignmentMode = .right
        }

        widgetLayer.frame = CGRect(origin: origin, size: size)
    }

    private func updateWidgetText() {
        if !editorConfiguration.activeWidgets.isEmpty {
            updateDataDrivenWidgets()
            return
        }

        clearDataDrivenWidgetLayers()
        if editorConfiguration.layers.showWidgets && editorConfiguration.clockCalendar.isEnabled {
            updateClockCalendarText()
            return
        }

        guard widgetConfiguration.isEnabled else {
            clearLegacyWidgetLayer()
            return
        }

        let now = Date()
        var lines: [String] = []

        if widgetConfiguration.showClock {
            lines.append(Self.clockFormatter.string(from: now))
        }

        if widgetConfiguration.showDate {
            lines.append(Self.dateFormatter.string(from: now))
        }

        if widgetConfiguration.showBattery {
            lines.append(Self.batterySummary())
        }

        widgetLayer.string = lines.joined(separator: "\n")
        widgetLayer.isHidden = lines.isEmpty
        widgetLayer.backgroundColor = lines.isEmpty ? nil : NSColor.black.withAlphaComponent(0.28).cgColor
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private func updateEditorPresentation() {
        playerLayer?.isHidden = !editorConfiguration.layers.showVideo
        tintLayer.opacity = Float(min(max(editorConfiguration.blurTint.tintOpacity, 0), 0.85))
        fogLayer.isHidden = !editorConfiguration.layers.showAmbientFog
        cloudLayer.isHidden = !editorConfiguration.layers.showMovingClouds
        foregroundLayer.isHidden = !editorConfiguration.layers.showForegroundVignette
        updateVideoFilters()
        updateCustomText()
        updateWidgetFrame()
        updateWidgetText()
        updateWidgetTimer()
        updateInteractionMonitoring()
        updateCloudAnimation()
    }

    private func clearLegacyWidgetLayer() {
        widgetLayer.string = nil
        widgetLayer.isHidden = true
        widgetLayer.backgroundColor = nil
    }

    private func clearDataDrivenWidgetLayers() {
        widgetRuntime.unloadAll()
    }

    private func updateWidgetTimer() {
        let shouldRun = !editorConfiguration.activeWidgets.isEmpty ||
            widgetConfiguration.isEnabled ||
            (editorConfiguration.layers.showWidgets && editorConfiguration.clockCalendar.isEnabled)

        if shouldRun, widgetTimer == nil {
            widgetTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateWidgetText()
                }
            }
        } else if !shouldRun {
            widgetTimer?.invalidate()
            widgetTimer = nil
        }
    }

    private func updateVideoFilters() {
        var filters: [Any] = []

        let color = editorConfiguration.color
        if color.saturation != 1 || color.brightness != 0 || color.contrast != 1,
           let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(color.saturation, forKey: kCIInputSaturationKey)
            colorControls.setValue(color.brightness, forKey: kCIInputBrightnessKey)
            colorControls.setValue(color.contrast, forKey: kCIInputContrastKey)
            filters.append(colorControls)
        }

        if color.hueDegrees != 0,
           let hueAdjust = CIFilter(name: "CIHueAdjust") {
            hueAdjust.setValue(color.hueDegrees * .pi / 180, forKey: kCIInputAngleKey)
            filters.append(hueAdjust)
        }

        if editorConfiguration.blurTint.blurRadius > 0,
           let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(editorConfiguration.blurTint.blurRadius, forKey: kCIInputRadiusKey)
            filters.append(blur)
        }

        playerLayer?.filters = filters
    }

    private func fadeInPlayerLayer(_ layer: CALayer) {
        layer.removeAnimation(forKey: "wallpaper-alpha-restore")
        layer.opacity = 1

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 0.22
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "wallpaper-alpha-restore")
    }

    private func updateCustomText() {
        let text = editorConfiguration.customText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        customTextLayer.isHidden = !editorConfiguration.layers.showCustomText || text.isEmpty
        customTextLayer.string = text
        customTextLayer.font = editorConfiguration.customText.fontName as CFTypeRef
        customTextLayer.fontSize = editorConfiguration.customText.fontSize
        customTextLayer.alignmentMode = caAlignment(for: editorConfiguration.customText.alignment)
        updateCustomTextFrame()
    }

    private func updateCustomTextFrame() {
        let size = CGSize(width: min(520, max(260, bounds.width * 0.34)), height: 98)
        let origin = origin(for: editorConfiguration.customText.position, size: size, inset: 36)
        customTextLayer.frame = CGRect(origin: origin, size: size)
    }

    private func updateClockCalendarText() {
        let clock = editorConfiguration.clockCalendar
        guard clock.isEnabled else {
            clearLegacyWidgetLayer()
            return
        }

        widgetLayer.isHidden = false
        widgetLayer.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        widgetLayer.font = clock.fontName as CFTypeRef
        widgetLayer.fontSize = clock.fontSize
        widgetLayer.alignmentMode = caAlignment(for: clock.alignment)

        let now = Date()
        var lines: [String] = []

        if clock.showClock {
            lines.append((clock.use24HourClock ? Self.twentyFourHourClockFormatter : Self.twelveHourClockFormatter).string(from: now))
        }

        if clock.showCalendar {
            lines.append(Self.dateFormatter.string(from: now))
        }

        widgetLayer.string = lines.joined(separator: "\n")
    }

    private func updateDataDrivenWidgets() {
        clearLegacyWidgetLayer()
        let widgets = editorConfiguration.layers.showWidgets ? editorConfiguration.activeWidgets : []
        widgetRuntime.render(widgets: widgets, on: layer, bounds: bounds)
    }

    private func updateDataDrivenWidgetFrames() {
        let widgets = editorConfiguration.layers.showWidgets ? editorConfiguration.activeWidgets : []
        widgetRuntime.render(widgets: widgets, on: layer, bounds: bounds)
    }

    private func configureCloudLayer() {
        cloudLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for index in 0..<5 {
            let puff = CALayer()
            let width = CGFloat(170 + index * 34)
            let height = CGFloat(42 + index * 6)
            puff.frame = CGRect(x: CGFloat(index) * 180, y: CGFloat(60 + index * 44), width: width, height: height)
            puff.cornerRadius = height / 2
            puff.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            cloudLayer.addSublayer(puff)
        }
    }

    private func updateCloudAnimation() {
        cloudLayer.removeAnimation(forKey: "cloud-drift")
        guard editorConfiguration.layers.showMovingClouds else { return }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = cloudLayer.position.x - 60
        animation.toValue = cloudLayer.position.x + 60
        animation.duration = 18 / editorConfiguration.clampedPlaybackSpeed
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cloudLayer.add(animation, forKey: "cloud-drift")
    }

    private func updateInteractionMonitoring() {
        let interactions = editorConfiguration.mouseInteraction
        cursorLayer.isHidden = !interactions.particlesFollowMouse

        if interactions.particlesFollowMouse || interactions.parallaxDepth {
            if interactionTimer == nil {
                interactionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.sampleMouse()
                    }
                }
            }
        } else {
            interactionTimer?.invalidate()
            interactionTimer = nil
            cloudLayer.setAffineTransform(.identity)
            customTextLayer.setAffineTransform(.identity)
        }

        if interactions.clickReactions {
            if clickEventMonitor == nil {
                clickEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    Task { @MainActor in
                        self?.showClickReaction(atScreenPoint: event.locationInWindow)
                    }
                }
            }
        } else if let clickEventMonitor {
            NSEvent.removeMonitor(clickEventMonitor)
            self.clickEventMonitor = nil
        }
    }

    private func sampleMouse() {
        guard editorConfiguration.mouseInteraction.particlesFollowMouse || editorConfiguration.mouseInteraction.parallaxDepth,
              let window else {
            return
        }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)

        if editorConfiguration.mouseInteraction.particlesFollowMouse {
            cursorLayer.position = localPoint
        }

        if editorConfiguration.mouseInteraction.parallaxDepth {
            let xOffset = (localPoint.x / max(1, bounds.width) - 0.5) * 24
            let yOffset = (localPoint.y / max(1, bounds.height) - 0.5) * 18
            cloudLayer.setAffineTransform(CGAffineTransform(translationX: xOffset, y: yOffset))
            customTextLayer.setAffineTransform(CGAffineTransform(translationX: xOffset * 0.35, y: yOffset * 0.35))
        }
    }

    private func showClickReaction(atScreenPoint screenPoint: CGPoint) {
        guard let window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        clickPulseLayer.position = convert(windowPoint, from: nil)
        clickPulseLayer.removeAllAnimations()
        clickPulseLayer.opacity = 1
        clickPulseLayer.transform = CATransform3DIdentity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        fade.duration = 0.5
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1.4
        scale.duration = 0.5
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fade, scale]
        group.duration = 0.5
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        clickPulseLayer.add(group, forKey: "click-pulse")
    }

    private func legacyWidgetPosition() -> WallpaperOverlayPosition {
        switch widgetConfiguration.position {
        case .topLeft:
            .topLeft
        case .topRight:
            .topRight
        case .bottomLeft:
            .bottomLeft
        case .bottomRight:
            .bottomRight
        }
    }

    private func origin(for position: WallpaperOverlayPosition, size: CGSize, inset: CGFloat) -> CGPoint {
        switch position {
        case .topLeft:
            CGPoint(x: inset, y: bounds.height - size.height - inset)
        case .topRight:
            CGPoint(x: bounds.width - size.width - inset, y: bounds.height - size.height - inset)
        case .center:
            CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        case .bottomLeft:
            CGPoint(x: inset, y: inset)
        case .bottomRight:
            CGPoint(x: bounds.width - size.width - inset, y: inset)
        }
    }

    private func caAlignment(for alignment: WallpaperTextAlignment) -> CATextLayerAlignmentMode {
        switch alignment {
        case .left:
            .left
        case .center:
            .center
        case .right:
            .right
        }
    }

    private static let twelveHourClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let twentyFourHourClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func batterySummary() -> String {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int,
              max > 0 else {
            return "Battery --"
        }

        return "Battery \(Int((Double(current) / Double(max) * 100).rounded()))%"
    }

    deinit {
        if securityScopeIsActive, let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }
}
