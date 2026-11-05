import AppKit
import MacWallpaperEngineCore
import SwiftData
import SwiftUI


struct ColorEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Color Tuning") {
            TuningSlider("Hue", value: $configuration.color.hueDegrees, range: -180...180, suffix: "deg")
            TuningSlider("Saturation", value: $configuration.color.saturation, range: 0...2, suffix: "x")
            TuningSlider("Brightness", value: $configuration.color.brightness, range: -1...1, suffix: "")
            TuningSlider("Contrast", value: $configuration.color.contrast, range: 0.5...2, suffix: "x")
            TuningSlider("Blur", value: $configuration.blurTint.blurRadius, range: 0...24, suffix: "px")
            TuningSlider("Dark tint behind icons", value: $configuration.blurTint.tintOpacity, range: 0...0.85, suffix: "")
        }
    }
}

struct PlaybackEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Playback") {
            TuningSlider("Speed", value: $configuration.playbackSpeed, range: 0.25...2, suffix: "x")
        }
    }
}

struct LayerEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Components") {
            Toggle("Video layer", isOn: $configuration.layers.showVideo)
            Toggle("Background fog", isOn: $configuration.layers.showAmbientFog)
            Toggle("Moving clouds", isOn: $configuration.layers.showMovingClouds)
            Toggle("Foreground vignette", isOn: $configuration.layers.showForegroundVignette)
            Toggle("Custom text layer", isOn: $configuration.layers.showCustomText)
            Toggle("Clock and calendar widgets", isOn: $configuration.layers.showWidgets)
        }
    }
}

struct TextEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Custom Text") {
            TextField("Quote or daily reminder", text: $configuration.customText.text, axis: .vertical)
                .lineLimit(2...4)

            InstalledFontPicker("Font", selection: $configuration.customText.fontName)
            TuningSlider("Font size", value: $configuration.customText.fontSize, range: 16...96, suffix: "pt")
            AlignmentPicker(selection: $configuration.customText.alignment)
            PositionPicker(selection: $configuration.customText.position)
        }
    }
}

struct ClockCalendarEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Clock and Calendar") {
            Toggle("Show clock", isOn: $configuration.clockCalendar.showClock)
            Toggle("Show calendar", isOn: $configuration.clockCalendar.showCalendar)
            Toggle("Use 24-hour time", isOn: $configuration.clockCalendar.use24HourClock)
            InstalledFontPicker("Font", selection: $configuration.clockCalendar.fontName)
            TuningSlider("Font size", value: $configuration.clockCalendar.fontSize, range: 14...72, suffix: "pt")
            AlignmentPicker(selection: $configuration.clockCalendar.alignment)
            PositionPicker(selection: $configuration.clockCalendar.position)
        }
    }
}

struct InteractionEditorSection: View {
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Mouse Interaction") {
            Toggle("Particles follow the cursor", isOn: $configuration.mouseInteraction.particlesFollowMouse)
            Toggle("Parallax depth", isOn: $configuration.mouseInteraction.parallaxDepth)
            Toggle("Click reactions", isOn: $configuration.mouseInteraction.clickReactions)
        }
    }
}

struct ThemeSyncEditorSection: View {
    let assets: [WallpaperAssetRecord]
    @Binding var configuration: WallpaperEditorConfiguration

    var body: some View {
        EditorSectionCard(title: "Theme and Schedule Sync") {
            Picker("Sync mode", selection: $configuration.themeSync.mode) {
                ForEach(WallpaperThemeSyncMode.allCases, id: \.self) { mode in
                    Text(title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if configuration.themeSync.mode == .systemAppearance {
                AssetVariantPicker("Light mode wallpaper", assets: assets, selection: $configuration.themeSync.lightAssetID)
                AssetVariantPicker("Dark mode wallpaper", assets: assets, selection: $configuration.themeSync.darkAssetID)
            }

            if configuration.themeSync.mode == .timeOfDay {
                AssetVariantPicker("Day wallpaper", assets: assets, selection: $configuration.themeSync.dayAssetID)
                AssetVariantPicker("Night wallpaper", assets: assets, selection: $configuration.themeSync.nightAssetID)
                TimeOfDayPicker("Day starts", minutes: $configuration.themeSync.dayStartMinutes)
                TimeOfDayPicker("Night starts", minutes: $configuration.themeSync.nightStartMinutes)
            }
        }
    }

    private func title(for mode: WallpaperThemeSyncMode) -> String {
        switch mode {
        case .off:
            "Off"
        case .systemAppearance:
            "Light/Dark"
        case .timeOfDay:
            "Schedule"
        }
    }
}

struct EditorSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) {
        self.title = title
        self._value = value
        self.range = range
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }

    private var formattedValue: String {
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        return suffix.isEmpty ? formatted : "\(formatted) \(suffix)"
    }
}

struct InstalledFontPicker: View {
    let title: String
    @Binding var selection: String
    private static let fonts = NSFontManager.shared.availableFonts.sorted()

    init(_ title: String, selection: Binding<String>) {
        self.title = title
        self._selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            if !Self.fonts.contains(selection) {
                Text(selection).tag(selection)
            }
            ForEach(Self.fonts, id: \.self) { fontName in
                Text(fontName).tag(fontName)
            }
        }
        .frame(maxWidth: 360)
    }
}

struct AlignmentPicker: View {
    @Binding var selection: WallpaperTextAlignment

    var body: some View {
        Picker("Alignment", selection: $selection) {
            ForEach(WallpaperTextAlignment.allCases, id: \.self) { alignment in
                Text(alignment.rawValue.capitalized).tag(alignment)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct PositionPicker: View {
    @Binding var selection: WallpaperOverlayPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(WallpaperOverlayPosition.allCases, id: \.self) { position in
                    Button {
                        selection = position
                    } label: {
                        Text(title(for: position))
                            .lineLimit(1)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                selection == position ? Color.accentColor : Color.secondary.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .foregroundStyle(selection == position ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                }
            }
        }
    }

    private func title(for position: WallpaperOverlayPosition) -> String {
        switch position {
        case .topLeft:
            "Top Left"
        case .topRight:
            "Top Right"
        case .center:
            "Center"
        case .bottomLeft:
            "Bottom Left"
        case .bottomRight:
            "Bottom Right"
        }
    }
}

struct AssetVariantPicker: View {
    let title: String
    let assets: [WallpaperAssetRecord]
    @Binding var selection: UUID?

    init(_ title: String, assets: [WallpaperAssetRecord], selection: Binding<UUID?>) {
        self.title = title
        self.assets = assets
        self._selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Use current").tag(Optional<UUID>.none)
            ForEach(assets) { asset in
                Text(asset.displayName).tag(Optional(asset.id))
            }
        }
    }
}

struct TimeOfDayPicker: View {
    let title: String
    @Binding var minutes: Int

    init(_ title: String, minutes: Binding<Int>) {
        self.title = title
        self._minutes = minutes
    }

    var body: some View {
        DatePicker(title, selection: Binding {
            date(fromMinutes: minutes)
        } set: { newDate in
            minutes = minutes(from: newDate)
        }, displayedComponents: .hourAndMinute)
    }

    private func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: max(0, min(23, minutes / 60)),
            minute: max(0, min(59, minutes % 60)),
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
