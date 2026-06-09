import AppKit
import MacWallpaperEngineCore
import SwiftData
import SwiftUI

struct WallpaperEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]

    @State private var selectedAssetID: UUID?

    private var selectedAsset: WallpaperAssetRecord? {
        if let selectedAssetID,
           let selected = assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }

        return assignedOrFirstAsset
    }

    private var assignedOrFirstAsset: WallpaperAssetRecord? {
        if let assignedAssetID = profiles.compactMap(\.assignedAssetID).first,
           let assigned = assets.first(where: { $0.id == assignedAssetID }) {
            return assigned
        }

        return assets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wallpaper Creator")
                    .font(.largeTitle.weight(.semibold))
                Text("Trim, tune, layer, and personalize the active wallpaper without leaving the app.")
                    .foregroundStyle(.secondary)
            }

            if assets.isEmpty {
                ContentUnavailableView(
                    "No Wallpaper to Edit",
                    systemImage: "wand.and.stars",
                    description: Text("Import a local video first, then come back here to create variants and widgets.")
                )
            } else if let selectedAsset {
                Picker("Wallpaper", selection: Binding(
                    get: { selectedAsset.id },
                    set: { selectedAssetID = $0 }
                )) {
                    ForEach(assets) { asset in
                        Text(asset.displayName).tag(asset.id)
                    }
                }
                .frame(maxWidth: 420)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TrimEditorSection(asset: selectedAsset, configuration: configurationBinding(for: selectedAsset))
                        ColorEditorSection(configuration: configurationBinding(for: selectedAsset))
                        PlaybackEditorSection(configuration: configurationBinding(for: selectedAsset))
                        LayerEditorSection(configuration: configurationBinding(for: selectedAsset))
                        TextEditorSection(configuration: configurationBinding(for: selectedAsset))
                        ClockCalendarEditorSection(configuration: configurationBinding(for: selectedAsset))
                        InteractionEditorSection(configuration: configurationBinding(for: selectedAsset))
                        ThemeSyncEditorSection(
                            assets: assets,
                            configuration: configurationBinding(for: selectedAsset)
                        )
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .padding(24)
        .onAppear {
            selectedAssetID = selectedAsset?.id
        }
        .onChange(of: assets.map(\.id)) {
            if selectedAsset == nil {
                selectedAssetID = assets.first?.id
            }
        }
    }

    private func configurationBinding(for asset: WallpaperAssetRecord) -> Binding<WallpaperEditorConfiguration> {
        Binding {
            asset.editorConfiguration
        } set: { newValue in
            appState.updateEditorConfiguration(
                for: asset,
                assets: assets,
                profiles: profiles,
                modelContext: modelContext
            ) { configuration in
                configuration = newValue
            }
        }
    }
}

struct TrimEditorSection: View {
    let asset: WallpaperAssetRecord
    @Binding var configuration: WallpaperEditorConfiguration

    private var duration: Double {
        max(0, asset.duration)
    }

    var body: some View {
        EditorSectionCard(title: "Snippet") {
            if VideoTrimConfiguration.shouldShowTrimControls(duration: duration) {
                VStack(alignment: .leading, spacing: 12) {
                    DualHandleRangeSlider(
                        lowerValue: trimStartBinding,
                        upperValue: trimEndBinding,
                        bounds: 0...max(1, duration),
                        minimumDistance: 0.5
                    )

                    HStack {
                        TimeValueField(title: "Start", value: trimStartBinding, upperBound: max(0, duration - 0.5))
                        TimeValueField(title: "End", value: trimEndBinding, upperBound: duration)
                    }

                    Text("Videos longer than 60 seconds can loop a precise snippet. Short clips loop as-is.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("This clip is short enough to loop as-is. Trim controls appear for videos 60 seconds or longer.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimStartBinding: Binding<Double> {
        Binding {
            configuration.videoTrim.normalized(forDuration: duration).startSeconds
        } set: { newValue in
            let end = configuration.videoTrim.effectiveEndSeconds(forDuration: duration)
            configuration.videoTrim.startSeconds = min(max(0, newValue), max(0, end - 0.5))
            configuration.videoTrim.endSeconds = max(configuration.videoTrim.startSeconds + 0.5, end)
        }
    }

    private var trimEndBinding: Binding<Double> {
        Binding {
            configuration.videoTrim.effectiveEndSeconds(forDuration: duration)
        } set: { newValue in
            let start = configuration.videoTrim.normalized(forDuration: duration).startSeconds
            configuration.videoTrim.endSeconds = min(max(start + 0.5, newValue), duration)
        }
    }
}

private struct TimeValueField: View {
    let title: String
    @Binding var value: Double
    let upperBound: Double

    var body: some View {
        Stepper(value: $value, in: 0...max(0, upperBound), step: 0.1) {
            LabeledContent(title, value: formatted(value))
        }
        .frame(maxWidth: 260)
    }

    private func formatted(_ value: Double) -> String {
        let totalTenths = Int((value * 10).rounded())
        let totalSeconds = totalTenths / 10
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60)).\(totalTenths % 10)"
    }
}

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
    private let fonts = NSFontManager.shared.availableFonts.sorted()

    init(_ title: String, selection: Binding<String>) {
        self.title = title
        self._selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(fonts, id: \.self) { fontName in
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
        Picker("Position", selection: $selection) {
            ForEach(WallpaperOverlayPosition.allCases, id: \.self) { position in
                Text(title(for: position)).tag(position)
            }
        }
        .pickerStyle(.segmented)
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
