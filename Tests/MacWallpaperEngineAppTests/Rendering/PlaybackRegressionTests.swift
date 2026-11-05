import AppKit
import AVFoundation
import MacWallpaperEngineCore
@testable import MacWallpaperEngineApp
import Testing

@Suite("Playback regressions", .serialized)
@MainActor
struct PlaybackRegressionTests {
    @Test
    func frameCapHonorsPlaybackSpeedAndCanReturnToNative() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        try await SmoothVideoExporterTests.writeTestMovie(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let view = VideoWallpaperView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        defer { view.prepareForClose() }
        var config = WallpaperEditorConfiguration.default
        config.playbackSpeed = 2
        view.setVideo(url: url, assetDuration: 0.1, playlistItems: [], layoutMode: .fill, editorConfiguration: config)
        view.apply(.capped(fps: 15))
        let deadline = Date().addingTimeInterval(5)
        while view.playbackFrameDuration == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let duration = try #require(view.playbackFrameDuration)
        #expect(abs(duration.seconds - 2.0 / 15) < 0.0001)
        #expect(view.playbackRate == 2)
        view.apply(.full)
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.playbackFrameDuration == nil)
        view.apply(.capped(fps: 120))
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.playbackFrameDuration == nil)
        #expect(view.playbackRate == 2)
    }
    @Test
    func cosmeticEditsReusePlayerAndClearRestoresDesktop() async throws {
        _ = NSApplication.shared
        let display = try #require(WallpaperDisplay.displays().first)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        try await SmoothVideoExporterTests.writeTestMovie(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = WallpaperWindowController(display: display)
        defer { controller.close() }
        var configuration = WallpaperEditorConfiguration.default
        controller.setVideo(url: url, assetDuration: 0.1, playlistItems: [], layoutMode: .fill, editorConfiguration: configuration)
        let identity = try #require(controller.playbackIdentity)
        configuration.color.brightness = 0.2
        configuration.customText.text = "Edited"
        configuration.playbackSpeed = 2
        controller.setVideo(url: url, assetDuration: 0.1, playlistItems: [], layoutMode: .fit, editorConfiguration: configuration)
        #expect(controller.playbackIdentity == identity)
        #expect(controller.isVisible)
        controller.setVideo(url: nil, assetDuration: 0, playlistItems: [], layoutMode: .fill, editorConfiguration: .default)
        #expect(controller.playbackIdentity == nil)
        #expect(!controller.isVisible)
    }

    @Test
    func pauseAndPosterStopAllOverlayTimers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        try await SmoothVideoExporterTests.writeTestMovie(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let view = VideoWallpaperView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        defer { view.prepareForClose() }
        var configuration = WallpaperEditorConfiguration.default
        configuration.clockCalendar.showClock = true
        configuration.layers.showMovingClouds = true
        configuration.mouseInteraction.parallaxDepth = true
        view.setVideo(url: url, assetDuration: 0.1, playlistItems: [], layoutMode: .fill, editorConfiguration: configuration)
        #expect(view.hasActiveTimers)
        view.apply(.paused(reason: .manual))
        #expect(!view.hasActiveTimers)
        view.apply(.full)
        #expect(view.hasActiveTimers)
        view.apply(.posterFrame(reason: .lowPowerMode))
        #expect(!view.hasActiveTimers)
        configuration.customText.text = "Still paused"
        view.setEditorConfiguration(configuration)
        #expect(!view.hasActiveTimers)
    }

    @Test
    func missingFileThrowsInsteadOfReturningUnplayableURL() {
        let record = WallpaperAssetRecord(asset: WallpaperAsset(displayName: "Missing", originalFilename: "missing.mov",
            bookmarkData: Data(), duration: 1, pixelWidth: 128, pixelHeight: 72, codecSummary: "H264",
            lastKnownPath: "/tmp/\(UUID()).mov"))
        #expect(throws: (any Error).self) { try record.resolvedURL() }
    }

    @Test
    func widgetRefreshRateAndLayoutAreRespected() {
        let registry = WidgetModuleRegistry()
        let module = CountingWidgetModule()
        registry.register(kind: .clock) { module }
        let host = WidgetRuntimeHost(registry: registry)
        let parent = CALayer()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        var widget = DesktopWidgetConfiguration.clock()
        widget.refresh.intervalSeconds = 5
        let start = Date(timeIntervalSince1970: 1_000)
        host.render(widgets: [widget], on: parent, bounds: bounds, now: start)
        host.render(widgets: [widget], on: parent, bounds: bounds, now: start.addingTimeInterval(1))
        #expect(module.updates == 1)
        host.render(widgets: [widget], on: parent, bounds: bounds, now: start.addingTimeInterval(5))
        #expect(module.updates == 2)
        widget.style.scale = 4
        #expect(bounds.contains(WidgetRuntimeLayout.frame(for: widget, in: bounds)))
        host.render(widgets: [], on: parent, bounds: bounds)
        #expect(parent.sublayers?.isEmpty != false)
    }
}

@MainActor
private final class CountingWidgetModule: DesktopWidgetModule {
    let kind: DesktopWidgetKind = .clock
    var updates = 0
    func update(layer: CATextLayer, widget: DesktopWidgetConfiguration, context: WidgetRenderContext) { updates += 1 }
}
