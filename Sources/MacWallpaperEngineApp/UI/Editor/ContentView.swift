import AppKit
import MacWallpaperEngineCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \WallpaperAssetRecord.createdAt, order: .reverse) private var assets: [WallpaperAssetRecord]
    @Query private var profiles: [DisplayProfileRecord]

    @State private var selectedAssetID: UUID?
    @State private var selectedWidgetID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isDropTargeted = false
    @State private var didInitializeSelection = false

    private var selectedAsset: WallpaperAssetRecord? {
        if let selectedAssetID,
           let selected = assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }

        return assets.first
    }

    private var profileFingerprints: [String] {
        profiles.map { profile in
            let assignedID = profile.assignedAssetID?.uuidString ?? "none"
            return "\(profile.screenID)-\(assignedID)-\(profile.layoutModeRawValue)"
        }
    }

    private var assetIDs: [UUID] {
        assets.map(\.id)
    }

    private var preferredSelectedAssetID: UUID? {
        let availableAssetIDs = Set(assetIDs)
        if let firstDisplayID = WallpaperDisplay.displays().first?.idString,
           let assignedAssetID = profiles.first(where: { $0.screenID == firstDisplayID })?.assignedAssetID,
           availableAssetIDs.contains(assignedAssetID) {
            return assignedAssetID
        }

        return profiles
            .compactMap(\.assignedAssetID)
            .first { availableAssetIDs.contains($0) } ?? assets.first?.id
    }

    private var hasValidSelection: Bool {
        guard let selectedAssetID else { return false }
        return assetIDs.contains(selectedAssetID)
    }

    private var editorFingerprints: [String] {
        assets.map(\.editorFingerprint)
    }

    var body: some View {
        ContentWorkspace(
            selectedAsset: selectedAsset,
            assets: assets,
            profiles: profiles,
            selectedAssetID: $selectedAssetID,
            selectedWidgetID: $selectedWidgetID,
            columnVisibility: $columnVisibility,
            isDropTargeted: $isDropTargeted
        )
        .toolbar {
            ContentToolbar(
                selectedAsset: selectedAsset,
                assets: assets,
                profiles: profiles,
                columnVisibility: $columnVisibility,
                modelContext: modelContext
            )
        }
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                appState.importVideo(url, modelContext: modelContext)
            }
            return !urls.isEmpty
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .onAppear {
            if !hasValidSelection {
                selectedAssetID = preferredSelectedAssetID
            }
            didInitializeSelection = true
            appState.start()
        }
        .onChange(of: selectedAssetID) { oldValue, newValue in
            guard didInitializeSelection,
                  oldValue != nil,
                  let newValue,
                  let selected = assets.first(where: { $0.id == newValue }) else {
                return
            }

            appState.setAsset(selected, for: nil, modelContext: modelContext)
        }
        .onChange(of: assetIDs) {
            if !hasValidSelection {
                selectedAssetID = preferredSelectedAssetID
            }
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onChange(of: editorFingerprints) {
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onChange(of: profileFingerprints) {
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            appState.reconcile(assets: assets, profiles: profiles)
        }
    }
}

private struct ContentWorkspace: View {
    let selectedAsset: WallpaperAssetRecord?
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedAssetID: UUID?
    @Binding var selectedWidgetID: UUID?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var isDropTargeted: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MasterLibrarySidebar(
                assets: assets,
                profiles: profiles,
                selectedAssetID: $selectedAssetID,
                isDropTargeted: $isDropTargeted
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } content: {
            CenterCanvasWorkspace(
                selectedAsset: selectedAsset,
                assets: assets,
                profiles: profiles,
                selectedWidgetID: $selectedWidgetID
            )
            .navigationSplitViewColumnWidth(min: 480, ideal: 780)
        } detail: {
            InspectorSidebar(
                selectedAsset: selectedAsset,
                assets: assets,
                profiles: profiles,
                selectedWidgetID: $selectedWidgetID
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
        }
    }
}

private struct MasterLibrarySidebar: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedAssetID: UUID?
    @Binding var isDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library")
                    .font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        appState.chooseVideo(modelContext: modelContext)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 26, height: 20)
                    }
                    .help("Choose local videos")

                    Button(role: .destructive) {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 26, height: 20)
                    }
                    .disabled(selectedAsset == nil)
                    .help("Remove selected wallpaper")
                }
            }
            .padding([.top, .horizontal], 14)

            if assets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Drop videos here")
                        .font(.headline)
                    Text("Local MP4, MOV, M4V, and QuickTime-playable movies only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedAssetID) {
                    ForEach(assets) { asset in
                        SidebarAssetRow(asset: asset)
                            .tag(Optional(asset.id))
                            .contextMenu {
                                Button {
                                    appState.revealWallpaperFile(asset)
                                } label: {
                                    Label("Show Video in Finder", systemImage: "folder")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    remove(asset)
                                } label: {
                                    Label("Remove Wallpaper", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var selectedAsset: WallpaperAssetRecord? {
        if let selectedAssetID,
           let selected = assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }

        return assets.first
    }

    private func removeSelected() {
        guard let selectedAsset else { return }
        remove(selectedAsset)
    }

    private func remove(_ asset: WallpaperAssetRecord) {
        selectedAssetID = assets.first { $0.id != asset.id }?.id
        appState.removeWallpaper(asset, assets: assets, profiles: profiles, modelContext: modelContext)
    }
}

private struct SidebarAssetRow: View {
    let asset: WallpaperAssetRecord

    var body: some View {
        HStack(spacing: 10) {
            if let image = PosterFrameCache.image(for: asset.posterFrameFilename) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 54, height: 36)
                    .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(asset.aspectDescription) · \(formattedDuration(asset.duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedDuration(_ duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return "Unknown" }
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

private struct CenterCanvasWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let selectedAsset: WallpaperAssetRecord?
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        if let selectedAsset {
            VStack(spacing: 14) {
                LivePreviewPane(
                    asset: selectedAsset,
                    configuration: selectedAsset.editorConfiguration,
                    selectedWidgetID: $selectedWidgetID
                )
                .aspectRatio(previewAspect(for: selectedAsset), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360, alignment: .top)

                ContextualLowerPane(
                    asset: selectedAsset,
                    assets: assets,
                    profiles: profiles,
                    selectedWidgetID: $selectedWidgetID
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160, idealHeight: 220, maxHeight: 280)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                "No Wallpaper Selected",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("Import or select a local video from the library.")
            )
        }
    }

    private func previewAspect(for asset: WallpaperAssetRecord) -> CGFloat {
        CGFloat(
            asset.editorConfiguration.canvasResolution.aspectRatio(
                fallbackWidth: Double(max(1, asset.pixelWidth)),
                fallbackHeight: Double(max(1, asset.pixelHeight))
            )
        )
    }
}

private struct LivePreviewPane: View {
    let asset: WallpaperAssetRecord
    let configuration: WallpaperEditorConfiguration
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)

            if let image = PosterFrameCache.image(for: asset.posterFrameFilename) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(configuration.layers.showVideo ? 1 : 0.12)
                    .saturation(configuration.color.saturation)
                    .brightness(configuration.color.brightness)
                    .contrast(configuration.color.contrast)
            } else {
                LinearGradient(colors: [.black, .blue.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            Color.black.opacity(configuration.blurTint.tintOpacity)

            if configuration.layers.showAmbientFog {
                LinearGradient(colors: [.white.opacity(0.18), .clear, .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            if configuration.layers.showForegroundVignette {
                RadialGradient(colors: [.clear, .black.opacity(0.48)], center: .center, startRadius: 80, endRadius: 500)
            }

            ForEach(configuration.activeWidgets) { widget in
                PreviewWidgetBadge(widget: widget, isSelected: selectedWidgetID == widget.id)
                    .onTapGesture {
                        selectedWidgetID = widget.id
                    }
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.displayName)
                            .font(.headline)
                        Text(configuration.playlist.isMultiVideo ? "Playlist · \(configuration.playlist.assetIDs.count) videos" : "Single video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(configuration.canvasResolution.displayTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct PreviewWidgetBadge: View {
    let widget: DesktopWidgetConfiguration
    let isSelected: Bool

    var body: some View {
        Text(widget.name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(isSelected ? 0.56 : 0.32), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.white.opacity(widget.style.opacity))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? .blue : .white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: widget.layout.anchor))
            .padding(28)
    }

    private func alignment(for anchor: WidgetAnchor) -> Alignment {
        switch anchor {
        case .absolute, .topRight:
            .topTrailing
        case .topLeft:
            .topLeading
        case .center:
            .center
        case .bottomLeft:
            .bottomLeading
        case .bottomRight:
            .bottomTrailing
        }
    }
}

private struct ContextualLowerPane: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if asset.editorConfiguration.playlist.isMultiVideo {
                PlaylistOrderingPane(asset: asset, assets: assets, profiles: profiles)
            } else if VideoTrimConfiguration.shouldShowTrimControls(duration: asset.duration) {
                TrimmingOptimizationPane(asset: asset, assets: assets, profiles: profiles)
            } else {
                QuickFlowPane(asset: asset, assets: assets, profiles: profiles, selectedWidgetID: $selectedWidgetID)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
    }
}

private struct TrimmingOptimizationPane: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]

    var body: some View {
        let configuration = asset.editorConfiguration
        let snippet = configuration.videoTrim.performanceSnippet(forDuration: asset.duration)
        let lower = Binding<Double> {
            snippet.startSeconds
        } set: { newValue in
            updateTrim(start: newValue, end: nil)
        }
        let upper = Binding<Double> {
            snippet.effectiveEndSeconds(forDuration: asset.duration)
        } set: { newValue in
            updateTrim(start: nil, end: newValue)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline Trimmer")
                    .font(.headline)
                Spacer()
                SmoothCopyMenu(asset: asset)
                Button("Export Optimized Snippet") {
                    appState.exportOptimizedSnippet(
                        for: asset,
                        assets: assets,
                        profiles: profiles,
                        modelContext: modelContext
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            DualHandleRangeSlider(
                lowerValue: lower,
                upperValue: upper,
                bounds: 0...max(1, asset.duration),
                minimumDistance: min(30, max(0.5, asset.duration)),
                maximumDistance: min(60, max(1, asset.duration))
            )

            Text("Selection is capped to 30-60 seconds when the source is long, so exported snippets are easier on battery and RAM.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func updateTrim(start: Double?, end: Double?) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            let current = configuration.videoTrim.performanceSnippet(forDuration: asset.duration)
            let proposedStart = start ?? current.startSeconds
            let proposedEnd = end ?? current.effectiveEndSeconds(forDuration: asset.duration)
            let clampedEnd = min(max(proposedStart + 30, proposedEnd), min(asset.duration, proposedStart + 60))
            configuration.videoTrim = VideoTrimConfiguration(startSeconds: min(proposedStart, max(0, clampedEnd - 30)), endSeconds: clampedEnd)
        }
    }
}

private struct SmoothCopyMenu: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    @State private var isShowingCustomSettings = false
    @State private var targetFPS = 120
    @State private var resolutionMode: SmoothCopyResolutionMode = .native
    @State private var customWidth = 1_920
    @State private var customHeight = 1_080
    @State private var interpolationMode: SmoothVideoInterpolationMode = .opticalFlow

    var body: some View {
        Button("Generate Smooth Copy") {
            primeCustomDimensionsFromAsset()
            isShowingCustomSettings = true
        }
        .help("Create a local generated-frame video copy")
        .popover(isPresented: $isShowingCustomSettings) {
            SmoothCopySettingsPopover(
                asset: asset,
                targetFPS: $targetFPS,
                resolutionMode: $resolutionMode,
                customWidth: $customWidth,
                customHeight: $customHeight,
                interpolationMode: $interpolationMode
            ) {
                appState.exportSmoothCopy(for: asset, preset: customPreset, modelContext: modelContext)
                isShowingCustomSettings = false
            } onRevealGeneratedVideos: {
                appState.revealGeneratedVideosFolder()
            }
        }
        .onAppear {
            primeCustomDimensionsFromAsset()
        }
        .onChange(of: asset.id) {
            primeCustomDimensionsFromAsset()
        }
    }

    private var customPreset: SmoothVideoExportPreset {
        SmoothVideoExportPreset(
            title: "Custom Smooth Copy",
            targetFPS: targetFPS,
            maximumLongEdge: resolutionMode.maximumLongEdge,
            customDimensions: customDimensions,
            interpolationMode: interpolationMode
        )
    }

    private var customDimensions: SmoothVideoExportDimensions? {
        guard resolutionMode == .custom else { return nil }
        return SmoothVideoExportDimensions(width: customWidth, height: customHeight)
    }

    private func primeCustomDimensionsFromAsset() {
        guard customWidth == 1_920 && customHeight == 1_080 else { return }
        customWidth = max(2, asset.pixelWidth)
        customHeight = max(2, asset.pixelHeight)
    }
}

private enum SmoothCopyResolutionMode: String, CaseIterable, Identifiable {
    case native
    case fhd1080p
    case qhd1440p
    case fourK
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native:
            "Native"
        case .fhd1080p:
            "1080p"
        case .qhd1440p:
            "1440p"
        case .fourK:
            "4K"
        case .custom:
            "Custom"
        }
    }

    var maximumLongEdge: Int? {
        switch self {
        case .native, .custom:
            nil
        case .fhd1080p:
            1_920
        case .qhd1440p:
            2_560
        case .fourK:
            3_840
        }
    }
}

private struct SmoothCopySettingsPopover: View {
    let asset: WallpaperAssetRecord
    @Binding var targetFPS: Int
    @Binding var resolutionMode: SmoothCopyResolutionMode
    @Binding var customWidth: Int
    @Binding var customHeight: Int
    @Binding var interpolationMode: SmoothVideoInterpolationMode
    let onGenerate: () -> Void
    let onRevealGeneratedVideos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smooth Copy Settings")
                    .font(.headline)
                Text(asset.displayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            FPSCapControl(title: "Frame rate", fps: $targetFPS)

            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution")
                    .font(.subheadline.weight(.medium))

                Picker("Resolution", selection: $resolutionMode) {
                    ForEach(SmoothCopyResolutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if resolutionMode == .custom {
                HStack(spacing: 8) {
                    TextField("Width", value: $customWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Text("x")
                        .foregroundStyle(.secondary)
                    TextField("Height", value: $customHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Text("px")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

            Picker("Interpolation", selection: $interpolationMode) {
                ForEach(SmoothVideoInterpolationMode.allCases, id: \.self) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text("Output: \(outputSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    onRevealGeneratedVideos()
                } label: {
                    Label("Show Generated Videos", systemImage: "folder")
                }

                Spacer()

                Button("Generate") {
                    targetFPS = PlaybackFrameRateCap.clampedTargetFPS(targetFPS)
                    normalizeCustomDimensions()
                    onGenerate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var outputSummary: String {
        let preset = SmoothVideoExportPreset(
            title: "Custom Smooth Copy",
            targetFPS: targetFPS,
            maximumLongEdge: resolutionMode.maximumLongEdge,
            customDimensions: resolutionMode == .custom
                ? SmoothVideoExportDimensions(width: customWidth, height: customHeight)
                : nil,
            interpolationMode: interpolationMode
        )
        let dimensions = preset.outputDimensions(sourceWidth: asset.pixelWidth, sourceHeight: asset.pixelHeight)
        return "\(preset.normalizedTargetFPS) fps, \(dimensions.width)x\(dimensions.height), \(interpolationMode.displayTitle)"
    }

    private func normalizeCustomDimensions() {
        guard resolutionMode == .custom else { return }
        let preset = SmoothVideoExportPreset(
            title: "Custom Smooth Copy",
            targetFPS: targetFPS,
            customDimensions: SmoothVideoExportDimensions(width: customWidth, height: customHeight),
            interpolationMode: interpolationMode
        )
        let dimensions = preset.outputDimensions(sourceWidth: asset.pixelWidth, sourceHeight: asset.pixelHeight)
        customWidth = dimensions.width
        customHeight = dimensions.height
    }
}

private struct PlaylistOrderingPane: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sequential Flow")
                    .font(.headline)
                Spacer()
                Menu("Add Video") {
                    ForEach(assets) { candidate in
                        Button(candidate.displayName) {
                            append(candidate)
                        }
                    }
                }
            }

            List {
                ForEach(orderedAssets) { playlistAsset in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(playlistAsset.displayName)
                        Spacer()
                        Text(formattedDuration(playlistAsset.duration))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .onMove { source, destination in
                    move(from: source, to: destination)
                }
            }
            .frame(minHeight: 130)

            TuningSlider("Crossfade", value: crossfadeBinding, range: 0...4, suffix: "s")
        }
    }

    private var orderedAssets: [WallpaperAssetRecord] {
        asset.editorConfiguration.playlist.assetIDs.compactMap { id in
            assets.first { $0.id == id }
        }
    }

    private var crossfadeBinding: Binding<Double> {
        Binding {
            asset.editorConfiguration.playlist.crossfadeDuration
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                configuration.playlist.crossfadeDuration = value
            }
        }
    }

    private func append(_ candidate: WallpaperAssetRecord) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            if configuration.playlist.assetIDs.isEmpty {
                configuration.playlist.assetIDs = [asset.id]
            }
            if !configuration.playlist.assetIDs.contains(candidate.id) {
                configuration.playlist.assetIDs.append(candidate.id)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            configuration.playlist.move(from: source, to: destination)
        }
    }

    private func formattedDuration(_ duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return "Unknown" }
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

private struct QuickFlowPane: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                prompt
                Spacer(minLength: 12)
                actions
            }

            VStack(alignment: .leading, spacing: 10) {
                prompt
                actions
            }
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ready to Customize")
                .font(.headline)
            Text("Use the inspector to tune color, widgets, playlist order, and performance settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Create Playlist") {
                appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                    var ids = [asset.id]
                    if let nextAssetID = assets.first(where: { $0.id != asset.id })?.id {
                        ids.append(nextAssetID)
                    }
                    configuration.playlist.assetIDs = ids
                }
            }
            .disabled(assets.count < 2)

            Button("Add Clock") {
                addWidget(.clock())
            }

            SmoothCopyMenu(asset: asset)
        }
    }

    private func addWidget(_ widget: DesktopWidgetConfiguration) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            configuration.widgets.append(widget)
            selectedWidgetID = widget.id
        }
    }
}

private struct InspectorSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let selectedAsset: WallpaperAssetRecord?
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?
    @State private var selectedTab: InspectorDockTab = .layers

    var body: some View {
        HStack(spacing: 0) {
            InspectorIconDock(selection: $selectedTab, selectedWidgetID: $selectedWidgetID)
                .frame(width: 54)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selectedAsset {
                        InspectorHeader(asset: selectedAsset, title: panelTitle)
                        panelContent(for: selectedAsset)
                    } else {
                        ContentUnavailableView("Inspector", systemImage: "sidebar.right", description: Text("Select a wallpaper to edit."))
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: selectedWidgetID) {
            if selectedWidgetID != nil {
                selectedTab = .layers
            }
        }
    }

    private var panelTitle: String {
        if selectedWidgetID != nil {
            return "Widget"
        }

        return selectedTab.title
    }

    @ViewBuilder
    private func panelContent(for asset: WallpaperAssetRecord) -> some View {
        if selectedWidgetID != nil {
            SelectedWidgetInspector(
                asset: asset,
                assets: assets,
                profiles: profiles,
                selectedWidgetID: $selectedWidgetID
            )
        } else {
            let configuration = configurationBinding(for: asset)
            switch selectedTab {
            case .layers:
                WidgetLayerInspector(
                    asset: asset,
                    assets: assets,
                    profiles: profiles,
                    selectedWidgetID: $selectedWidgetID
                )
                LayerEditorSection(configuration: configuration)
                PlaybackEditorSection(configuration: configuration)
            case .text:
                TextEditorSection(configuration: configuration)
                ClockCalendarEditorSection(configuration: configuration)
            case .effects:
                ColorEditorSection(configuration: configuration)
                InteractionEditorSection(configuration: configuration)
            case .settings:
                PerformanceInspectorSection()
                ThemeSyncEditorSection(assets: assets, configuration: configuration)
            }
        }
    }

    private func configurationBinding(for asset: WallpaperAssetRecord) -> Binding<WallpaperEditorConfiguration> {
        Binding {
            asset.editorConfiguration
        } set: { newValue in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                configuration = newValue
            }
        }
    }

}

private struct InspectorHeader: View {
    let asset: WallpaperAssetRecord
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(asset.displayName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private enum InspectorDockTab: String, CaseIterable, Identifiable {
    case layers
    case text
    case effects
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layers:
            "Layers"
        case .text:
            "Text"
        case .effects:
            "Effects"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .layers:
            "square.3.layers.3d"
        case .text:
            "textformat"
        case .effects:
            "wand.and.stars"
        case .settings:
            "gearshape"
        }
    }
}

private struct InspectorIconDock: View {
    @Binding var selection: InspectorDockTab
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(InspectorDockTab.allCases) { tab in
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selection = tab
                        if tab != .layers {
                            selectedWidgetID = nil
                        }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(selection == tab ? .blue.opacity(0.16) : .clear)
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selection == tab ? .blue : .secondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .help(tab.title)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
        .animation(nil, value: selection)
    }
}

private struct PerformanceInspectorSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        EditorSectionCard(title: "Performance") {
            Toggle("Pause when covered", isOn: $appState.policy.pauseWhenCovered)
            Toggle("Pause during full-screen apps", isOn: $appState.policy.pauseDuringFullscreenApps)
            Toggle("Reduce on battery", isOn: $appState.policy.reduceOnBattery)
            FPSCapControl(title: "Battery FPS", fps: $appState.policy.batteryFPSCap)
            FPSCapControl(
                title: "Normal FPS",
                fps: Binding(
                    get: { appState.policy.normalFPSCap ?? 0 },
                    set: { appState.policy.normalFPSCap = $0 == 0 ? nil : $0 }
                ),
                allowsNative: true
            )
        }
    }
}

private struct WidgetLayerInspector: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?

    var body: some View {
        EditorSectionCard(title: "Widget Layers") {
            HStack {
                Button("Wallpaper") {
                    selectedWidgetID = nil
                }
                .buttonStyle(.bordered)

                Menu("Add") {
                    Button("Clock") { add(.clock()) }
                    Button("Hardware Monitor") { add(.hardwareMonitor()) }
                    Button("Weather") { add(.weather()) }
                }
            }

            ForEach(asset.editorConfiguration.widgets) { widget in
                HStack {
                    Button {
                        selectedWidgetID = widget.id
                    } label: {
                        HStack {
                            Image(systemName: icon(for: widget.kind))
                            Text(widget.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: visibilityBinding(for: widget.id))
                        .labelsHidden()
                }
                .padding(8)
                .background(selectedWidgetID == widget.id ? .blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func add(_ widget: DesktopWidgetConfiguration) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            configuration.widgets.append(widget)
            selectedWidgetID = widget.id
        }
    }

    private func visibilityBinding(for widgetID: UUID) -> Binding<Bool> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == widgetID }?.isVisible ?? false
        } set: { isVisible in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                configuration.widgets[index].isVisible = isVisible
            }
        }
    }

    private func icon(for kind: DesktopWidgetKind) -> String {
        switch kind {
        case .clock:
            "clock"
        case .hardwareMonitor:
            "cpu"
        case .weather:
            "cloud.sun"
        }
    }
}

private struct SelectedWidgetInspector: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var selectedWidgetID: UUID?

    private var widget: DesktopWidgetConfiguration? {
        guard let selectedWidgetID else { return nil }
        return asset.editorConfiguration.widgets.first { $0.id == selectedWidgetID }
    }

    var body: some View {
        if let widget {
            EditorSectionCard(title: "\(widget.name) Properties") {
                TextField("Name", text: widgetNameBinding(widget.id))
                Toggle("Visible", isOn: widgetVisibilityBinding(widget.id))

                switch widget.kind {
                case .clock:
                    ClockWidgetInspector(widgetID: widget.id, asset: asset, assets: assets, profiles: profiles)
                case .hardwareMonitor:
                    HardwareMonitorInspector(widgetID: widget.id, asset: asset, assets: assets, profiles: profiles)
                case .weather:
                    WeatherInspector(widgetID: widget.id, asset: asset, assets: assets, profiles: profiles)
                }

                WidgetStyleInspector(widgetID: widget.id, asset: asset, assets: assets, profiles: profiles)

                Button("Remove Widget", role: .destructive) {
                    remove(widget.id)
                }
            }
        }
    }

    private func widgetNameBinding(_ id: UUID) -> Binding<String> {
        widgetBinding(id, fallback: widget?.name ?? "", get: \.name) { $0.name = $1 }
    }

    private func widgetVisibilityBinding(_ id: UUID) -> Binding<Bool> {
        widgetBinding(id, fallback: widget?.isVisible ?? false, get: \.isVisible) { $0.isVisible = $1 }
    }

    private func widgetBinding<Value>(
        _ id: UUID,
        fallback: Value,
        get: @escaping (DesktopWidgetConfiguration) -> Value,
        set: @escaping (inout DesktopWidgetConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == id }.map(get) ?? fallback
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == id }) else { return }
                set(&configuration.widgets[index], value)
            }
        }
    }

    private func remove(_ id: UUID) {
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            configuration.widgets.removeAll { $0.id == id }
            selectedWidgetID = nil
        }
    }
}

private struct ClockWidgetInspector: View {
    let widgetID: UUID
    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Toggle("Show time", isOn: binding(\.clock.showTime, fallback: true) { $0.clock.showTime = $1 })
        Toggle("Show date", isOn: binding(\.clock.showDate, fallback: false) { $0.clock.showDate = $1 })
        Toggle("24-hour time", isOn: binding(\.clock.use24HourClock, fallback: false) { $0.clock.use24HourClock = $1 })
        InstalledFontPicker("Font", selection: binding(\.style.fontName, fallback: "Helvetica Neue") { $0.style.fontName = $1 })
    }

    private func binding<Value>(
        _ keyPath: KeyPath<DesktopWidgetConfiguration, Value>,
        fallback: Value,
        _ setter: @escaping (inout DesktopWidgetConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == widgetID }?[keyPath: keyPath] ?? fallback
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                setter(&configuration.widgets[index], value)
            }
        }
    }
}

private struct HardwareMonitorInspector: View {
    let widgetID: UUID
    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Toggle("Show CPU", isOn: binding(\.hardwareMonitor.showCPU, fallback: true) { $0.hardwareMonitor.showCPU = $1 })
        Toggle("Show RAM", isOn: binding(\.hardwareMonitor.showRAM, fallback: true) { $0.hardwareMonitor.showRAM = $1 })
        Picker("Graph style", selection: binding(\.hardwareMonitor.graphStyle, fallback: .compactText) { $0.hardwareMonitor.graphStyle = $1 }) {
            ForEach(HardwareGraphStyle.allCases, id: \.self) { style in
                Text(style.rawValue.capitalized).tag(style)
            }
        }
    }

    private func binding<Value>(
        _ keyPath: KeyPath<DesktopWidgetConfiguration, Value>,
        fallback: Value,
        _ setter: @escaping (inout DesktopWidgetConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == widgetID }?[keyPath: keyPath] ?? fallback
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                setter(&configuration.widgets[index], value)
            }
        }
    }
}

private struct WeatherInspector: View {
    let widgetID: UUID
    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TextField("Location label", text: binding(\.weather.locationLabel, fallback: "Local Weather") { $0.weather.locationLabel = $1 })
        Toggle("Use Celsius", isOn: binding(\.weather.useCelsius, fallback: false) { $0.weather.useCelsius = $1 })
        Text("Weather remains offline until a provider is explicitly configured.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func binding<Value>(
        _ keyPath: KeyPath<DesktopWidgetConfiguration, Value>,
        fallback: Value,
        _ setter: @escaping (inout DesktopWidgetConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == widgetID }?[keyPath: keyPath] ?? fallback
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                setter(&configuration.widgets[index], value)
            }
        }
    }
}

private struct WidgetStyleInspector: View {
    let widgetID: UUID
    let asset: WallpaperAssetRecord
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Picker("Anchor", selection: binding(\.layout.anchor, fallback: .topRight) { $0.layout.anchor = $1 }) {
            ForEach(WidgetAnchor.allCases, id: \.self) { anchor in
                Text(anchor.rawValue.capitalized).tag(anchor)
            }
        }
        Toggle("Lock to anchor", isOn: binding(\.layout.isAnchorLocked, fallback: true) { $0.layout.isAnchorLocked = $1 })
        InstalledFontPicker("Font", selection: binding(\.style.fontName, fallback: "Helvetica Neue") { $0.style.fontName = $1 })
        TuningSlider("X", value: binding(\.layout.x, fallback: 32) { $0.layout.x = $1 }, range: 0...3_840, suffix: "px")
        TuningSlider("Y", value: binding(\.layout.y, fallback: 32) { $0.layout.y = $1 }, range: 0...2_160, suffix: "px")
        TuningSlider("Scale", value: binding(\.style.scale, fallback: 1) { $0.style.scale = $1 }, range: 0.5...2.5, suffix: "x")
        TuningSlider("Opacity", value: binding(\.style.opacity, fallback: 1) { $0.style.opacity = $1 }, range: 0...1, suffix: "")
        ColorPicker("Foreground", selection: colorBinding(\.style.foregroundColor) { $0.style.foregroundColor = $1 })
        ColorPicker("Shadow", selection: colorBinding(\.style.shadowColor) { $0.style.shadowColor = $1 })
        TuningSlider("Shadow radius", value: binding(\.style.shadowRadius, fallback: 8) { $0.style.shadowRadius = $1 }, range: 0...24, suffix: "px")
        TuningSlider("Refresh", value: binding(\.refresh.intervalSeconds, fallback: 1) { $0.refresh.intervalSeconds = $1 }, range: 1...3_600, suffix: "s")
    }

    private func binding<Value>(
        _ keyPath: KeyPath<DesktopWidgetConfiguration, Value>,
        fallback: Value,
        _ setter: @escaping (inout DesktopWidgetConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            asset.editorConfiguration.widgets.first { $0.id == widgetID }?[keyPath: keyPath] ?? fallback
        } set: { value in
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                setter(&configuration.widgets[index], value)
            }
        }
    }

    private func colorBinding(
        _ keyPath: KeyPath<DesktopWidgetConfiguration, WidgetColor>,
        _ setter: @escaping (inout DesktopWidgetConfiguration, WidgetColor) -> Void
    ) -> Binding<Color> {
        Binding {
            let widgetColor = asset.editorConfiguration.widgets.first { $0.id == widgetID }?[keyPath: keyPath] ?? .white
            return Color(
                red: widgetColor.red,
                green: widgetColor.green,
                blue: widgetColor.blue,
                opacity: widgetColor.alpha
            )
        } set: { color in
            let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
            let widgetColor = WidgetColor(
                red: Double(nsColor.redComponent),
                green: Double(nsColor.greenComponent),
                blue: Double(nsColor.blueComponent),
                alpha: Double(nsColor.alphaComponent)
            )
            appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
                guard let index = configuration.widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                setter(&configuration.widgets[index], widgetColor)
            }
        }
    }
}

private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.blue.opacity(0.14))
            .stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42))
                    Text("Drop local videos to import")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.blue)
            }
            .padding(24)
            .allowsHitTesting(false)
    }
}
