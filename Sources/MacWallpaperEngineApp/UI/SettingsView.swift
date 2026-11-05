import MacWallpaperEngineCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WallpaperAssetRecord.createdAt, order: .reverse) private var assets: [WallpaperAssetRecord]
    @Query private var profiles: [DisplayProfileRecord]
    @State private var displays = WallpaperDisplay.displays()

    var body: some View {
        Form {
            Section("Playback") {
                PerformanceInspectorSection()
                Button("Reset Playback Settings") { appState.policy = .default }
            }
            Section("Displays") {
                ForEach(displays, id: \.id) { display in
                    Picker(display.name, selection: Binding<UUID?>(
                        get: { profiles.first { $0.screenID == display.idString }?.assignedAssetID },
                        set: { id in
                            appState.setAsset(assets.first { $0.id == id }, for: display, modelContext: modelContext)
                        }
                    )) {
                        Text("System Wallpaper").tag(nil as UUID?)
                        ForEach(assets) { asset in Text(asset.displayName).tag(Optional(asset.id)) }
                    }
                    Picker("\(display.name) Layout", selection: Binding(
                        get: { profiles.first { $0.screenID == display.idString }?.layoutMode ?? .fill },
                        set: { appState.setLayout($0, for: display, modelContext: modelContext) }
                    )) {
                        Text("Fill").tag(WallpaperLayoutMode.fill)
                        Text("Fit").tag(WallpaperLayoutMode.fit)
                        Text("Stretch").tag(WallpaperLayoutMode.stretch)
                    }
                }
                Button("Use System Wallpaper on All Displays") {
                    appState.setAsset(nil, for: nil, modelContext: modelContext)
                }
            }
            Section("General") {
                Toggle("Open at Login", isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                Button("Show Library Files in Finder") { NSWorkspace.shared.open(AppStorage.root) }
                Button("Show Generated Videos in Finder") { appState.revealGeneratedVideosFolder() }
                if appState.widgetConfiguration.isEnabled {
                    Button("Disable Legacy Desktop Widgets") { appState.widgetConfiguration = .init() }
                }
            }
            OperationStatusView()
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = WallpaperDisplay.displays()
        }
    }
}

struct OperationStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = appState.exportStatus {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(status).lineLimit(2)
                    Spacer()
                    Button("Cancel") { appState.cancelExport() }
                        .disabled(status == "Cancelling export...")
                }
            }
            if let error = appState.lastErrorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { appState.lastErrorMessage = nil } label: {
                        Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Error")
                }
            }
        }
        .font(.callout)
    }
}
