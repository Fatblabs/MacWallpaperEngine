import MacWallpaperEngineCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \WallpaperAssetRecord.createdAt, order: .reverse) private var assets: [WallpaperAssetRecord]
    @Query private var profiles: [DisplayProfileRecord]
    @State private var selectedTab = "library"
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Library", systemImage: "film.stack")
                    .tag("library")
                Label("Displays", systemImage: "display.2")
                    .tag("displays")
                Label("Editor", systemImage: "slider.horizontal.3")
                    .tag("editor")
                Label("Performance", systemImage: "speedometer")
                    .tag("performance")
                Label("Widgets", systemImage: "clock.badge")
                    .tag("widgets")
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch selectedTab {
                case "displays":
                    DisplaySettingsView(assets: assets, profiles: profiles)
                case "editor":
                    WallpaperEditorView(assets: assets, profiles: profiles)
                case "performance":
                    PerformanceSettingsView()
                case "widgets":
                    WidgetsView(assets: assets, profiles: profiles)
                default:
                    LibraryView(assets: assets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.chooseVideo(modelContext: modelContext)
                } label: {
                    Label("Choose Video", systemImage: "plus")
                }

                Button {
                    appState.toggleManualPause()
                } label: {
                    Label(appState.isManuallyPaused ? "Resume" : "Pause", systemImage: appState.isManuallyPaused ? "play.fill" : "pause.fill")
                }

                Toggle(isOn: $appState.isEditModeEnabled) {
                    Label("Edit Wallpaper", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
            }
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
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onChange(of: assets.map(\.id)) {
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onChange(of: assets.map(\.editorFingerprint)) {
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onChange(of: profiles.map { "\($0.screenID)-\($0.assignedAssetID?.uuidString ?? "none")-\($0.layoutModeRawValue)" }) {
            appState.reconcile(assets: assets, profiles: profiles)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            appState.reconcile(assets: assets, profiles: profiles)
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
