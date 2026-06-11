import AppKit
import MacWallpaperEngineCore

@MainActor
struct WidgetRenderContext {
    var now: Date
    var bounds: CGRect
    var backingScale: CGFloat

    static func current(bounds: CGRect) -> WidgetRenderContext {
        WidgetRenderContext(
            now: Date(),
            bounds: bounds,
            backingScale: NSScreen.main?.backingScaleFactor ?? 2
        )
    }
}

@MainActor
protocol DesktopWidgetModule: AnyObject {
    var kind: DesktopWidgetKind { get }

    func makeLayer(for widget: DesktopWidgetConfiguration, context: WidgetRenderContext) -> CATextLayer
    func update(layer: CATextLayer, widget: DesktopWidgetConfiguration, context: WidgetRenderContext)
    func unload(layer: CATextLayer)
}

@MainActor
extension DesktopWidgetModule {
    func makeLayer(for widget: DesktopWidgetConfiguration, context: WidgetRenderContext) -> CATextLayer {
        let layer = CATextLayer()
        layer.cornerRadius = 8
        layer.contentsScale = context.backingScale
        layer.masksToBounds = false
        return layer
    }

    func unload(layer: CATextLayer) {
        layer.removeFromSuperlayer()
    }

    func applyBaseStyle(
        to layer: CATextLayer,
        widget: DesktopWidgetConfiguration,
        context: WidgetRenderContext,
        alignment: CATextLayerAlignmentMode,
        text: String
    ) {
        layer.isHidden = text.isEmpty
        layer.string = text
        layer.contentsScale = context.backingScale
        layer.backgroundColor = text.isEmpty ? nil : NSColor.black.withAlphaComponent(0.28).cgColor
        layer.opacity = Float(min(max(widget.style.opacity, 0), 1))
        layer.foregroundColor = nsColor(widget.style.foregroundColor).cgColor
        layer.shadowColor = nsColor(widget.style.shadowColor).cgColor
        layer.shadowRadius = widget.style.shadowRadius
        layer.shadowOpacity = widget.style.shadowRadius > 0 ? 0.8 : 0
        layer.font = widget.style.fontName as CFTypeRef
        layer.fontSize = 24 * widget.style.scale
        layer.alignmentMode = alignment
        layer.frame = WidgetRuntimeLayout.frame(for: widget, in: context.bounds)
    }

    private func nsColor(_ color: WidgetColor) -> NSColor {
        NSColor(
            calibratedRed: min(max(color.red, 0), 1),
            green: min(max(color.green, 0), 1),
            blue: min(max(color.blue, 0), 1),
            alpha: min(max(color.alpha, 0), 1)
        )
    }
}

@MainActor
final class ClockWidgetModule: DesktopWidgetModule {
    let kind: DesktopWidgetKind = .clock

    func update(layer: CATextLayer, widget: DesktopWidgetConfiguration, context: WidgetRenderContext) {
        var lines: [String] = []
        if widget.clock.showTime {
            lines.append((widget.clock.use24HourClock ? Self.twentyFourHourClockFormatter : Self.twelveHourClockFormatter).string(from: context.now))
        }
        if widget.clock.showDate {
            lines.append(Self.dateFormatter.string(from: context.now))
        }

        applyBaseStyle(
            to: layer,
            widget: widget,
            context: context,
            alignment: caAlignment(for: widget.clock.alignment),
            text: lines.joined(separator: "\n")
        )
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

@MainActor
final class HardwareMonitorWidgetModule: DesktopWidgetModule {
    let kind: DesktopWidgetKind = .hardwareMonitor

    func update(layer: CATextLayer, widget: DesktopWidgetConfiguration, context: WidgetRenderContext) {
        var lines: [String] = []
        if widget.hardwareMonitor.showCPU {
            lines.append(cpuSummary(for: widget.hardwareMonitor.graphStyle))
        }
        if widget.hardwareMonitor.showRAM {
            lines.append(Self.memorySummary())
        }

        applyBaseStyle(
            to: layer,
            widget: widget,
            context: context,
            alignment: .left,
            text: lines.joined(separator: "\n")
        )
    }

    private func cpuSummary(for style: HardwareGraphStyle) -> String {
        switch style {
        case .compactText:
            "CPU active"
        case .bar:
            "CPU [active]"
        case .line:
            "CPU trend active"
        }
    }

    private static func memorySummary() -> String {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return "RAM --" }
        let totalGB = totalBytes / 1_073_741_824
        return "RAM \(totalGB.formatted(.number.precision(.fractionLength(0)))) GB"
    }
}

@MainActor
final class WeatherWidgetModule: DesktopWidgetModule {
    let kind: DesktopWidgetKind = .weather

    func update(layer: CATextLayer, widget: DesktopWidgetConfiguration, context: WidgetRenderContext) {
        let location = widget.weather.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = location.isEmpty ? "" : "\(location)\nWeather offline"

        applyBaseStyle(
            to: layer,
            widget: widget,
            context: context,
            alignment: .left,
            text: text
        )
    }
}

@MainActor
final class WidgetModuleRegistry {
    static let shared = WidgetModuleRegistry()

    private var factories: [DesktopWidgetKind: () -> DesktopWidgetModule] = [
        .clock: { ClockWidgetModule() },
        .hardwareMonitor: { HardwareMonitorWidgetModule() },
        .weather: { WeatherWidgetModule() }
    ]

    func register(kind: DesktopWidgetKind, factory: @escaping () -> DesktopWidgetModule) {
        factories[kind] = factory
    }

    func makeModule(for kind: DesktopWidgetKind) -> DesktopWidgetModule {
        factories[kind]?() ?? ClockWidgetModule()
    }
}

@MainActor
final class WidgetRuntimeHost {
    private struct HostedWidget {
        var kind: DesktopWidgetKind
        var module: DesktopWidgetModule
        var layer: CATextLayer
    }

    private var hostedWidgets: [UUID: HostedWidget] = [:]
    private let registry: WidgetModuleRegistry

    init(registry: WidgetModuleRegistry = .shared) {
        self.registry = registry
    }

    func render(widgets: [DesktopWidgetConfiguration], on parentLayer: CALayer?, bounds: CGRect) {
        guard let parentLayer else {
            unloadAll()
            return
        }

        let context = WidgetRenderContext.current(bounds: bounds)
        let activeWidgets = widgets.filter(\.emitsVisibleContent)
        let activeIDs = Set(activeWidgets.map(\.id))

        for id in hostedWidgets.keys where !activeIDs.contains(id) {
            unload(id: id)
        }

        for widget in activeWidgets {
            let hosted = hostedWidget(for: widget, context: context)
            if hosted.layer.superlayer == nil {
                parentLayer.addSublayer(hosted.layer)
            }
            hosted.module.update(layer: hosted.layer, widget: widget, context: context)
            hostedWidgets[widget.id] = hosted
        }
    }

    func unloadAll() {
        for id in Array(hostedWidgets.keys) {
            unload(id: id)
        }
    }

    private func hostedWidget(
        for widget: DesktopWidgetConfiguration,
        context: WidgetRenderContext
    ) -> HostedWidget {
        if let existing = hostedWidgets[widget.id],
           existing.kind == widget.kind {
            return existing
        }

        unload(id: widget.id)
        let module = registry.makeModule(for: widget.kind)
        let layer = module.makeLayer(for: widget, context: context)
        return HostedWidget(kind: widget.kind, module: module, layer: layer)
    }

    private func unload(id: UUID) {
        guard let hosted = hostedWidgets.removeValue(forKey: id) else { return }
        hosted.module.unload(layer: hosted.layer)
    }
}

private enum WidgetRuntimeLayout {
    static func frame(for widget: DesktopWidgetConfiguration, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 310 * widget.style.scale, height: 84 * widget.style.scale)

        if !widget.layout.isAnchorLocked || widget.layout.anchor == .absolute {
            return CGRect(
                x: min(max(0, widget.layout.x), max(0, bounds.width - size.width)),
                y: min(max(0, widget.layout.y), max(0, bounds.height - size.height)),
                width: size.width,
                height: size.height
            )
        }

        let inset: CGFloat = 32
        let origin: CGPoint
        switch widget.layout.anchor {
        case .absolute, .topRight:
            origin = CGPoint(x: bounds.width - size.width - inset, y: bounds.height - size.height - inset)
        case .topLeft:
            origin = CGPoint(x: inset, y: bounds.height - size.height - inset)
        case .center:
            origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        case .bottomLeft:
            origin = CGPoint(x: inset, y: inset)
        case .bottomRight:
            origin = CGPoint(x: bounds.width - size.width - inset, y: inset)
        }

        return CGRect(origin: origin, size: size)
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
