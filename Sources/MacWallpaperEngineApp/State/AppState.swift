import AppKit
import Foundation
import MacWallpaperEngineCore
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
    @Published var exportStatus: String?
    private var exportTask: Task<Void, Never>?
    private let runtimeEnabled: Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var editorSaveTask: Task<Void, Never>?
    private var pendingEditorSave: (() -> Void)?

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
    private var restoredSnapshot: PersistentWallpaperSnapshot?
    private var didObserveStoredAssetSnapshot = false
    private let policyDefaultsKey = "MacWallpaperEngine.playbackPolicy"
    private let widgetDefaultsKey = "MacWallpaperEngine.widgetConfiguration"

    init(runtimeEnabled: Bool = true) {
        self.runtimeEnabled = runtimeEnabled
        restoredSnapshot = WallpaperStateCache.load()
        loadPolicy()
        loadWidgetConfiguration()
    }

    func start() {
        guard runtimeEnabled, !didStart else { return }
        didStart = true

        wallpaperCoordinator.prepareForImmediateDisplay()
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

        observe(NSWorkspace.shared.notificationCenter,
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenSleeping = true
                self?.coverageMonitor.stop()
                self?.evaluatePlaybackPolicy()
            }
        }

        observe(NSWorkspace.shared.notificationCenter,
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenSleeping = false
                if self?.wallpaperCoordinator.activeDisplayIDs.isEmpty == false { self?.coverageMonitor.start() }
                self?.evaluatePlaybackPolicy()
            }
        }

        observe(NotificationCenter.default,
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileLatestConfiguration()
            }
        }

        observe(DistributedNotificationCenter.default,
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileLatestConfiguration()
            }
        }
    }

    private func observe(_ center: NotificationCenter, forName name: Notification.Name, object: Any?,
                         queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: queue, using: block)))
    }

    func stop() {
        editorSaveTask?.cancel()
        pendingEditorSave?()
        pendingEditorSave = nil
        exportTask?.cancel()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        coverageMonitor.stop()
        powerMonitor.stop()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        wallpaperCoordinator.stop()
        didStart = false
    }

    func bootstrapFromStore(modelContext: ModelContext) {
        start()

        do {
            var (storedAssets, storedProfiles) = try storedConfiguration(from: modelContext)

            if !storedAssets.isEmpty {
                didObserveStoredAssetSnapshot = true
            } else if shouldPreserveRestoredSnapshot {
                // Restore editable records too; a wallpaper-only fallback leaves an empty library.
                if let restoredSnapshot {
                    var seenIDs: Set<UUID> = []
                    for saved in restoredSnapshot.assets where seenIDs.insert(saved.id).inserted {
                        let record = WallpaperAssetRecord(asset: WallpaperAsset(
                            id: saved.id, displayName: saved.displayName, originalFilename: saved.originalFilename,
                            bookmarkData: saved.bookmarkData ?? Data(), duration: saved.duration,
                            pixelWidth: saved.pixelWidth, pixelHeight: saved.pixelHeight,
                            codecSummary: saved.codecSummary, lastKnownPath: saved.lastKnownPath,
                            posterFrameFilename: saved.posterFrameFilename
                        ))
                        record.editorConfigurationData = saved.editorConfigurationData
                        modelContext.insert(record)
                    }
                    for saved in restoredSnapshot.displayAssignments {
                        if let existing = storedProfiles.first(where: { $0.screenID == saved.screenID }) {
                            existing.assignedAssetID = saved.assetID
                        } else {
                            let profile = DisplayProfileRecord(screenID: saved.screenID, assignedAssetID: saved.assetID,
                                layoutMode: WallpaperLayoutMode(rawValue: saved.layoutModeRawValue) ?? .fill)
                            modelContext.insert(profile)
                            storedProfiles.append(profile)
                        }
                    }
                    try modelContext.save()
                    (storedAssets, storedProfiles) = try storedConfiguration(from: modelContext)
                    didObserveStoredAssetSnapshot = true
                }
            }

            reconcile(assets: storedAssets, profiles: storedProfiles)
        } catch {
            lastErrorMessage = "Startup restore failed: \(error.localizedDescription)"
        }
    }

    func reconcile(assets: [WallpaperAssetRecord], profiles: [DisplayProfileRecord]) {
        start()
        latestAssets = assets
        latestProfiles = profiles

        if assets.isEmpty && shouldPreserveRestoredSnapshot {
            if !applyRestoredSnapshotIfAvailable(status: "Restoring saved wallpaper...") {
                statusMessage = "Waiting for saved wallpaper..."
            }
            return
        }

        let hasRestorableSnapshot = restoredSnapshot?.activeAssetIDs.isEmpty == false
        if !assets.isEmpty {
            didObserveStoredAssetSnapshot = true
        }
        if !assets.isEmpty || didObserveStoredAssetSnapshot || !hasRestorableSnapshot {
            restoredSnapshot = WallpaperStateCache.save(assets: assets, profiles: profiles)
        }

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
                    editorConfiguration: .default,
                    playlistItems: []
                )
            }

            do {
                let url = try asset.resolvedURL()
                let playlistItems = playlistItems(for: asset, assets: assets)
                return WallpaperDisplayConfiguration(
                    display: display,
                    assetID: asset.id,
                    fileURL: url,
                    assetDuration: asset.duration,
                    layoutMode: profile?.layoutMode ?? .fill,
                    editorConfiguration: asset.editorConfiguration,
                    playlistItems: playlistItems
                )
            } catch {
                lastErrorMessage = "\(asset.displayName) is unavailable. Reveal or remove it from the library, then import a replacement."
                return WallpaperDisplayConfiguration(
                    display: display,
                    assetID: asset.id,
                    fileURL: nil,
                    assetDuration: asset.duration,
                    layoutMode: profile?.layoutMode ?? .fill,
                    editorConfiguration: asset.editorConfiguration,
                    playlistItems: []
                )
            }
        }

        if runtimeEnabled {
            wallpaperCoordinator.apply(configurations: configurations)
            if configurations.contains(where: { $0.fileURL != nil }), !isScreenSleeping {
                coverageMonitor.start()
            } else {
                coverageMonitor.stop()
            }
        }
        evaluatePlaybackPolicy()
    }

    private var shouldPreserveRestoredSnapshot: Bool {
        !didObserveStoredAssetSnapshot && restoredSnapshot?.activeAssetIDs.isEmpty == false
    }

    @discardableResult
    private func applyRestoredSnapshotIfAvailable(status: String) -> Bool {
        guard let restoredSnapshot else { return false }
        let configurations = WallpaperSnapshotResolver.configurations(
            from: restoredSnapshot,
            displays: WallpaperDisplay.displays(),
            appearance: currentWallpaperAppearance(),
            minuteOfDay: currentMinuteOfDay()
        )
        guard !configurations.isEmpty else { return false }

        wallpaperCoordinator.apply(configurations: configurations)
        evaluatePlaybackPolicy()
        statusMessage = status
        lastErrorMessage = nil
        return true
    }

    private func storedConfiguration(from modelContext: ModelContext) throws -> ([WallpaperAssetRecord], [DisplayProfileRecord]) {
        let assetDescriptor = FetchDescriptor<WallpaperAssetRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let profileDescriptor = FetchDescriptor<DisplayProfileRecord>()
        return (
            try modelContext.fetch(assetDescriptor),
            try modelContext.fetch(profileDescriptor)
        )
    }

    private func reconcileFromStore(modelContext: ModelContext) throws {
        let (storedAssets, storedProfiles) = try storedConfiguration(from: modelContext)
        reconcile(assets: storedAssets, profiles: storedProfiles)
    }

    private func reconcileLatestConfiguration() {
        guard !latestAssets.isEmpty else { return }
        reconcile(assets: latestAssets, profiles: latestProfiles)
    }

    func revealGeneratedVideosFolder() {
        do {
            let directory = try SmoothVideoExporter.generatedDirectory()
            NSWorkspace.shared.open(directory)
            statusMessage = "Opened generated videos folder"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Generated videos folder could not be opened: \(error.localizedDescription)"
        }
    }

    func revealWallpaperFile(_ asset: WallpaperAssetRecord) {
        do {
            let url = try asset.resolvedURL()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusMessage = "Showing \(asset.displayName) in Finder"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Video file could not be shown: \(error.localizedDescription)"
        }
    }

    func chooseVideo(modelContext: ModelContext) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Local Video"
        panel.message = "Pick an MP4, MOV, M4V, or other QuickTime-playable local movie."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie, .video]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importVideo(url, modelContext: modelContext)
        }
    }

    func importVideo(_ url: URL, modelContext: ModelContext) {
        statusMessage = "Preparing \(url.lastPathComponent)..."
        lastErrorMessage = nil

        Task {
            do {
                let preparedImport = try await Task.detached(priority: .utility) {
                    try ManagedVideoLibrary.prepareForImport(url)
                }.value

                try await importPreparedVideo(preparedImport, modelContext: modelContext)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func importPreparedVideo(_ preparedImport: PreparedVideoImport, modelContext: ModelContext) async throws {
        let metadata = try await LocalVideoImporter.metadata(for: preparedImport.url)
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
        asset.posterFrameFilename = await PosterFrameCache.generatePoster(for: preparedImport.url, assetID: asset.id)
        let existingAssets = try modelContext.fetch(FetchDescriptor<WallpaperAssetRecord>())
        if let existing = existingAssets.first(where: {
            URL(fileURLWithPath: $0.lastKnownPath).standardizedFileURL.resolvingSymlinksInPath() ==
                preparedImport.url.standardizedFileURL.resolvingSymlinksInPath()
        }) {
            PosterFrameCache.remove(filename: asset.posterFrameFilename)
            setAsset(existing, for: nil, modelContext: modelContext)
            return
        }
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
        try reconcileFromStore(modelContext: modelContext)
        statusMessage = preparedImport.wasCopied
            ? "Copied and imported \(metadata.originalFilename)"
            : "Imported \(metadata.originalFilename)"
        lastErrorMessage = nil
    }

    func setAsset(_ asset: WallpaperAssetRecord?, for display: WallpaperDisplay?, modelContext: ModelContext) {
        flushEditorChanges()
        do {
            let targetDisplays = display.map { [$0] } ?? WallpaperDisplay.displays()

            for targetDisplay in targetDisplays {
                let screenID = targetDisplay.idString
                let descriptor = FetchDescriptor<DisplayProfileRecord>(
                    predicate: #Predicate { $0.screenID == screenID }
                )
                let existing = try modelContext.fetch(descriptor).first

                if let existing {
                    existing.assignedAssetID = asset?.id
                    existing.updatedAt = Date()
                } else {
                    modelContext.insert(
                        DisplayProfileRecord(
                            screenID: targetDisplay.idString,
                            assignedAssetID: asset?.id,
                            layoutMode: .fill
                        )
                    )
                }
            }

            try modelContext.save()
            try reconcileFromStore(modelContext: modelContext)
            statusMessage = asset.map { "Set \($0.displayName)" } ?? "Restored system wallpaper"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeWallpaper(
        _ asset: WallpaperAssetRecord,
        assets: [WallpaperAssetRecord],
        profiles: [DisplayProfileRecord],
        modelContext: ModelContext
    ) {
        flushEditorChanges()
        let removedAssetID = asset.id
        let removedDisplayName = asset.displayName
        let removedPosterFrameFilename = asset.posterFrameFilename
        let remainingAssets = assets.filter { $0.id != removedAssetID }
        let replacementAssetID = remainingAssets.first?.id

        do {
            for profile in profiles where profile.assignedAssetID == removedAssetID {
                profile.assignedAssetID = replacementAssetID
                profile.updatedAt = Date()
            }

            for remainingAsset in remainingAssets {
                let currentConfiguration = remainingAsset.editorConfiguration
                let cleanedConfiguration = WallpaperReferenceCleanup.cleaned(
                    configuration: currentConfiguration,
                    removing: removedAssetID
                )
                if cleanedConfiguration != currentConfiguration {
                    remainingAsset.editorConfiguration = cleanedConfiguration
                }
            }

            modelContext.delete(asset)
            try modelContext.save()

            PosterFrameCache.remove(filename: removedPosterFrameFilename)
            reconcile(assets: remainingAssets, profiles: profiles)
            statusMessage = "Removed \(removedDisplayName)"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Wallpaper could not be removed: \(error.localizedDescription)"
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
            try reconcileFromStore(modelContext: modelContext)
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
        guard configuration != asset.editorConfiguration else { return }
        asset.editorConfiguration = configuration

        editorSaveTask?.cancel()
        pendingEditorSave = { [weak self] in
            guard let self else { return }
            do {
                try modelContext.save()
                self.reconcile(assets: assets, profiles: profiles)
                self.lastErrorMessage = nil
            } catch {
                self.lastErrorMessage = "Editor change could not be saved: \(error.localizedDescription)"
            }
        }
        editorSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            self?.pendingEditorSave?()
            self?.pendingEditorSave = nil
            self?.editorSaveTask = nil
        }
    }

    private func flushEditorChanges() {
        editorSaveTask?.cancel()
        editorSaveTask = nil
        pendingEditorSave?()
        pendingEditorSave = nil
    }

    func exportOptimizedSnippet(
        for asset: WallpaperAssetRecord,
        assets: [WallpaperAssetRecord],
        profiles: [DisplayProfileRecord],
        modelContext: ModelContext
    ) {
        guard exportTask == nil else { return }
        exportStatus = "Exporting optimized snippet..."
        exportTask = Task {
            defer { exportTask = nil; exportStatus = nil }
            do {
                let sourceURL = try asset.resolvedURL()
                let configuration = asset.editorConfiguration
                let outputURL = try await SnippetExporter.exportOptimizedSnippet(
                    sourceURL: sourceURL,
                    assetID: asset.id,
                    sourceDisplayName: asset.displayName,
                    duration: asset.duration,
                    trim: configuration.videoTrim
                )

                let metadata = try await LocalVideoImporter.metadata(for: outputURL)
                var newAsset = WallpaperAsset(
                    displayName: "\(metadata.displayName) Optimized",
                    originalFilename: metadata.originalFilename,
                    bookmarkData: metadata.bookmarkData,
                    duration: metadata.duration,
                    pixelWidth: metadata.pixelWidth,
                    pixelHeight: metadata.pixelHeight,
                    codecSummary: metadata.codecSummary,
                    lastKnownPath: metadata.lastKnownPath
                )
                newAsset.posterFrameFilename = await PosterFrameCache.generatePoster(for: outputURL, assetID: newAsset.id)
                let record = WallpaperAssetRecord(asset: newAsset)
                modelContext.insert(record)

                try modelContext.save()
                try reconcileFromStore(modelContext: modelContext)
                statusMessage = "Exported optimized snippet"
                lastErrorMessage = nil
            } catch is CancellationError {
                statusMessage = "Export cancelled"
            } catch {
                lastErrorMessage = "Snippet export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportSmoothCopy(
        for asset: WallpaperAssetRecord,
        preset: SmoothVideoExportPreset,
        modelContext: ModelContext
    ) {
        guard exportTask == nil else { return }

        do {
            let sourceURL = try asset.resolvedURL()
            let assetID = asset.id
            let sourceDisplayName = asset.displayName
            let exportLabel = preset.exportLabel
            statusMessage = "Generating \(exportLabel) smooth copy..."
            exportStatus = statusMessage
            lastErrorMessage = nil

            exportTask = Task {
                defer { exportTask = nil; exportStatus = nil }

                do {
                    let outputURL = try await SmoothVideoExporter.exportSmoothCopy(
                            sourceURL: sourceURL,
                            assetID: assetID,
                            sourceDisplayName: sourceDisplayName,
                            preset: preset,
                            progress: { [weak self] fraction in
                                await MainActor.run {
                                    self?.exportStatus = "Generating \(exportLabel): \(Int(fraction * 100))%"
                                }
                            }
                    )

                    let metadata = try await LocalVideoImporter.metadata(for: outputURL)
                    var newAsset = WallpaperAsset(
                        displayName: "\(sourceDisplayName) Smooth \(exportLabel)",
                        originalFilename: metadata.originalFilename,
                        bookmarkData: metadata.bookmarkData,
                        duration: metadata.duration,
                        pixelWidth: metadata.pixelWidth,
                        pixelHeight: metadata.pixelHeight,
                        codecSummary: metadata.codecSummary,
                        lastKnownPath: metadata.lastKnownPath
                    )
                    newAsset.posterFrameFilename = await PosterFrameCache.generatePoster(for: outputURL, assetID: newAsset.id)
                    modelContext.insert(WallpaperAssetRecord(asset: newAsset))

                    try modelContext.save()
                    try reconcileFromStore(modelContext: modelContext)
                    statusMessage = "Generated \(exportLabel) smooth copy"
                    lastErrorMessage = nil
                } catch is CancellationError {
                    statusMessage = "Export cancelled"
                } catch {
                    lastErrorMessage = "Smooth copy failed: \(error.localizedDescription)"
                }
            }
        } catch {
            lastErrorMessage = "Smooth copy failed: \(error.localizedDescription)"
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportStatus = "Cancelling export..."
    }

    private func assetForDisplay(
        _ display: WallpaperDisplay,
        profile: DisplayProfileRecord?,
        assets: [WallpaperAssetRecord]
    ) -> WallpaperAssetRecord? {
        if let profile {
            guard let assignedAssetID = profile.assignedAssetID,
                  let assigned = assets.first(where: { $0.id == assignedAssetID }) else { return nil }
            return resolvedVariant(for: assigned, assets: assets)
        }

        if let restoredAssetID = restoredSnapshot?.assignedAssetID(for: display.idString),
           let restoredAsset = assets.first(where: { $0.id == restoredAssetID }) {
            return resolvedVariant(for: restoredAsset, assets: assets)
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

    private func playlistItems(
        for asset: WallpaperAssetRecord,
        assets: [WallpaperAssetRecord]
    ) -> [WallpaperPlaylistItemConfiguration] {
        let configuration = asset.editorConfiguration
        let orderedIDs = configuration.playlist.assetIDs.isEmpty ? [asset.id] : configuration.playlist.assetIDs
        return orderedIDs.compactMap { id in
            guard let itemAsset = assets.first(where: { $0.id == id }),
                  let url = try? itemAsset.resolvedURL() else {
                return nil
            }

            return WallpaperPlaylistItemConfiguration(
                id: itemAsset.id,
                url: url,
                duration: itemAsset.duration
            )
        }
    }

    private func currentWallpaperAppearance() -> WallpaperAppearance {
        let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    private func currentMinuteOfDay() -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func evaluatePlaybackPolicy() {
        coverageMonitor.fullscreenCoverageThreshold = policy.fullscreenCoverageThreshold
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

        if playbackMode != strictestMode {
            playbackMode = strictestMode
        }

        let nextStatusMessage = status(for: strictestMode)
        if statusMessage != nextStatusMessage {
            statusMessage = nextStatusMessage
        }
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

        if case .capped(let a) = lhs, case .capped(let b) = rhs { return .capped(fps: min(a, b)) }
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
        guard let data = AppStorage.defaults.data(forKey: policyDefaultsKey),
              let decoded = try? JSONDecoder().decode(PlaybackPolicy.self, from: data) else {
            return
        }
        policy = decoded
    }

    private func savePolicy() {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        AppStorage.defaults.set(data, forKey: policyDefaultsKey)
    }

    private func loadWidgetConfiguration() {
        guard let data = AppStorage.defaults.data(forKey: widgetDefaultsKey),
              let decoded = try? JSONDecoder().decode(WidgetOverlayConfiguration.self, from: data) else {
            return
        }
        widgetConfiguration = decoded
    }

    private func saveWidgetConfiguration() {
        guard let data = try? JSONEncoder().encode(widgetConfiguration) else { return }
        AppStorage.defaults.set(data, forKey: widgetDefaultsKey)
    }
}
