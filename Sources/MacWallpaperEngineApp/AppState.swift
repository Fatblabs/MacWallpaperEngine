import AppKit
import Foundation
import MacWallpaperEngineCore
import Observation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var playbackMode: PlaybackMode = .full
    @Published var statusMessage: String = "Ready"
    @Published var lastErrorMessage: String?
    @Published var isManuallyPaused: Bool = false {
        didSet { evaluatePlaybackPolicy() }
    }
    @Published var isEditModeEnabled: Bool = false {
        didSet { wallpaperCoordinator.setEditMode(isEditModeEnabled) }
    }
    @Published var policy: PlaybackPolicy = .default {
        didSet {
            savePolicy()
            evaluatePlaybackPolicy()
        }
    }
    @Published var widgetConfiguration = WidgetOverlayConfiguration() {
        didSet {
            saveWidgetConfiguration()
            wallpaperCoordinator.setWidgetConfiguration(widgetConfiguration)
        }
    }
    @Published var launchAtLoginEnabled: Bool = LaunchAtLoginController.isEnabled

    let wallpaperCoordinator = WallpaperCoordinator()

    private let policyEngine = PlaybackPolicyEngine()
    private let coverageMonitor = WindowCoverageMonitor()
    private let powerMonitor = PowerStateMonitor()
    private var screenStates: [UInt32: ScreenRuntimeState] = [:]
    private var isScreenSleeping = false
    private var didStart = false
    private var scheduleTimer: Timer?
    private var latestAssets: [WallpaperAssetRecord] = []
    private var latestProfiles: [DisplayProfileRecord] = []
    private let policyDefaultsKey = "MacWallpaperEngine.playbackPolicy"
    private let widgetDefaultsKey = "MacWallpaperEngine.widgetConfiguration"

    init() {
        loadPolicy()
        loadWidgetConfiguration()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        wallpaperCoordinator.start()
        wallpaperCoordinator.setWidgetConfiguration(widgetConfiguration)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileLatestConfiguration()
            }
        }
        powerMonitor.onChange = { [weak self] in
            Task { @MainActor in
                self?.evaluatePlaybackPolicy()
            }
        }
        powerMonitor.start()

        coverageMonitor.onUpdate = { [weak self] states in
            Task { @MainActor in
                guard let self else { return }
                self.screenStates = Dictionary(uniqueKeysWithValues: states.map { ($0.displayID, $0) })
                self.evaluatePlaybackPolicy()
            }
        }
        coverageMonitor.start()

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenSleeping = true
                self?.evaluatePlaybackPolicy()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenSleeping = false
                self?.evaluatePlaybackPolicy()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.wallpaperCoordinator.start()
                self?.evaluatePlaybackPolicy()
            }
        }

        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileLatestConfiguration()
            }
        }
    }

    func reconcile(assets: [WallpaperAssetRecord], profiles: [DisplayProfileRecord]) {
        start()
        latestAssets = assets
        latestProfiles = profiles

        let configurations = WallpaperDisplay.displays().compactMap { display -> WallpaperDisplayConfiguration? in
            let profile = profiles.first { $0.screenID == display.idString }
            let asset = assetForDisplay(display, profile: profile, assets: assets)

            guard let asset else {
                return WallpaperDisplayConfiguration(
                    display: display,
                    assetID: nil,
                    fileURL: nil,
                    assetDuration: 0,
                    layoutMode: .fill,
                    editorConfiguration: .default
                )
            }

            do {
                let url = try asset.resolvedURL()
                return WallpaperDisplayConfiguration(
                    display: display,
                    assetID: asset.id,
                    fileURL: url,
                    assetDuration: asset.duration,
                    layoutMode: profile?.layoutMode ?? .fill,
                    editorConfiguration: asset.editorConfiguration
                )
            } catch {
                return WallpaperDisplayConfiguration(
                    display: display,
                    assetID: asset.id,
                    fileURL: nil,
                    assetDuration: asset.duration,
                    layoutMode: profile?.layoutMode ?? .fill,
                    editorConfiguration: asset.editorConfiguration
                )
            }
        }

        wallpaperCoordinator.apply(configurations: configurations)
        evaluatePlaybackPolicy()
    }

    private func reconcileLatestConfiguration() {
        guard !latestAssets.isEmpty else { return }
        reconcile(assets: latestAssets, profiles: latestProfiles)
    }

    func chooseVideo(modelContext: ModelContext) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Local Video"
        panel.message = "Pick an MP4, MOV, M4V, or other QuickTime-playable local movie."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie, .video]

        if panel.runModal() == .OK, let url = panel.url {
            importVideo(url, modelContext: modelContext)
        }
    }

    func importVideo(_ url: URL, modelContext: ModelContext) {
        do {
            let metadata = try LocalVideoImporter.metadata(for: url)
            var asset = WallpaperAsset(
                displayName: metadata.displayName,
                originalFilename: metadata.originalFilename,
                bookmarkData: metadata.bookmarkData,
                duration: metadata.duration,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                codecSummary: metadata.codecSummary,
                lastKnownPath: metadata.lastKnownPath
            )
            asset.posterFrameFilename = PosterFrameCache.generatePoster(for: url, assetID: asset.id)
            let record = WallpaperAssetRecord(asset: asset)
            modelContext.insert(record)

            for display in WallpaperDisplay.displays() {
                let screenID = display.idString
                let descriptor = FetchDescriptor<DisplayProfileRecord>(
                    predicate: #Predicate { $0.screenID == screenID }
                )
                let existing = try modelContext.fetch(descriptor).first
                if let existing {
                    existing.assignedAssetID = record.id
                    existing.updatedAt = Date()
                } else {
                    modelContext.insert(
                        DisplayProfileRecord(
                            screenID: display.idString,
                            assignedAssetID: record.id,
                            layoutMode: .fill
                        )
                    )
                }
            }

            try modelContext.save()
            statusMessage = "Imported \(metadata.originalFilename)"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setAsset(_ asset: WallpaperAssetRecord, for display: WallpaperDisplay?, modelContext: ModelContext) {
        do {
            let targetDisplays = display.map { [$0] } ?? WallpaperDisplay.displays()

            for targetDisplay in targetDisplays {
                let screenID = targetDisplay.idString
                let descriptor = FetchDescriptor<DisplayProfileRecord>(
                    predicate: #Predicate { $0.screenID == screenID }
                )
                let existing = try modelContext.fetch(descriptor).first

                if let existing {
                    existing.assignedAssetID = asset.id
                    existing.updatedAt = Date()
                } else {
                    modelContext.insert(
                        DisplayProfileRecord(
                            screenID: targetDisplay.idString,
                            assignedAssetID: asset.id,
                            layoutMode: .fill
                        )
                    )
                }
            }

            try modelContext.save()
            statusMessage = "Set \(asset.displayName)"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setLayout(_ layoutMode: WallpaperLayoutMode, for display: WallpaperDisplay, modelContext: ModelContext) {
        do {
            let screenID = display.idString
            let descriptor = FetchDescriptor<DisplayProfileRecord>(
                predicate: #Predicate { $0.screenID == screenID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.layoutMode = layoutMode
            } else {
                modelContext.insert(DisplayProfileRecord(screenID: display.idString, assignedAssetID: nil, layoutMode: layoutMode))
            }

            try modelContext.save()
            statusMessage = "Updated \(display.name)"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleManualPause() {
        isManuallyPaused.toggle()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginController.isEnabled
            lastErrorMessage = nil
        } catch {
            launchAtLoginEnabled = LaunchAtLoginController.isEnabled
            lastErrorMessage = "Launch at login could not be updated: \(error.localizedDescription)"
        }
    }

    func updateEditorConfiguration(
        for asset: WallpaperAssetRecord,
        assets: [WallpaperAssetRecord],
        profiles: [DisplayProfileRecord],
        modelContext: ModelContext,
        mutate: (inout WallpaperEditorConfiguration) -> Void
    ) {
        var configuration = asset.editorConfiguration
        mutate(&configuration)
        asset.editorConfiguration = configuration

        do {
            try modelContext.save()
            reconcile(assets: assets, profiles: profiles)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Editor change could not be saved: \(error.localizedDescription)"
        }
    }

    private func assetForDisplay(
        _ display: WallpaperDisplay,
        profile: DisplayProfileRecord?,
        assets: [WallpaperAssetRecord]
    ) -> WallpaperAssetRecord? {
        if let assignedAssetID = profile?.assignedAssetID,
           let assigned = assets.first(where: { $0.id == assignedAssetID }) {
            return resolvedVariant(for: assigned, assets: assets)
        }

        guard let first = assets.first else { return nil }
        return resolvedVariant(for: first, assets: assets)
    }

    private func resolvedVariant(
        for assigned: WallpaperAssetRecord,
        assets: [WallpaperAssetRecord]
    ) -> WallpaperAssetRecord {
        let configuration = assigned.editorConfiguration
        let variantID = configuration.themeSync.effectiveAssetID(
            defaultAssetID: assigned.id,
            appearance: currentWallpaperAppearance(),
            minuteOfDay: currentMinuteOfDay()
        )

        return assets.first(where: { $0.id == variantID }) ?? assigned
    }

    private func currentWallpaperAppearance() -> WallpaperAppearance {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    private func currentMinuteOfDay() -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func evaluatePlaybackPolicy() {
        let displayIDs = wallpaperCoordinator.activeDisplayIDs
        guard !displayIDs.isEmpty else { return }

        var strictestMode: PlaybackMode = .full

        for displayID in displayIDs {
            let screenState = screenStates[displayID]
            let context = PlaybackContext(
                displayID: displayID,
                desktopCoverage: screenState?.desktopCoverage ?? 0,
                isFullscreenAppCoveringDisplay: screenState?.isFullscreenCovered ?? false,
                powerSource: powerMonitor.powerSource,
                isLowPowerModeEnabled: powerMonitor.isLowPowerModeEnabled,
                thermalPressure: powerMonitor.thermalPressure,
                isScreenSleeping: isScreenSleeping,
                isManuallyPaused: isManuallyPaused
            )
            let mode = policyEngine.mode(for: context, policy: policy)
            wallpaperCoordinator.apply(mode, to: displayID)
            strictestMode = stricterMode(strictestMode, mode)
        }

        playbackMode = strictestMode
        statusMessage = status(for: strictestMode)
    }

    private func stricterMode(_ lhs: PlaybackMode, _ rhs: PlaybackMode) -> PlaybackMode {
        func rank(_ mode: PlaybackMode) -> Int {
            switch mode {
            case .full:
                0
            case .capped:
                1
            case .posterFrame:
                2
            case .paused:
                3
            }
        }

        return rank(rhs) > rank(lhs) ? rhs : lhs
    }

    private func status(for mode: PlaybackMode) -> String {
        switch mode {
        case .full:
            "Playing"
        case .capped(let fps):
            "Reduced to \(fps) fps"
        case .posterFrame(let reason):
            "Showing poster frame: \(reason.rawValue)"
        case .paused(let reason):
            "Paused: \(reason.rawValue)"
        }
    }

    private func loadPolicy() {
        guard let data = UserDefaults.standard.data(forKey: policyDefaultsKey),
              let decoded = try? JSONDecoder().decode(PlaybackPolicy.self, from: data) else {
            return
        }
        policy = decoded
    }

    private func savePolicy() {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        UserDefaults.standard.set(data, forKey: policyDefaultsKey)
    }

    private func loadWidgetConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: widgetDefaultsKey),
              let decoded = try? JSONDecoder().decode(WidgetOverlayConfiguration.self, from: data) else {
            return
        }
        widgetConfiguration = decoded
    }

    private func saveWidgetConfiguration() {
        guard let data = try? JSONEncoder().encode(widgetConfiguration) else { return }
        UserDefaults.standard.set(data, forKey: widgetDefaultsKey)
    }
}
