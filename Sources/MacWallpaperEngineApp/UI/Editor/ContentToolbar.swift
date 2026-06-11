import MacWallpaperEngineCore
import SwiftData
import SwiftUI

struct ContentToolbar: ToolbarContent {
    @EnvironmentObject private var appState: AppState

    let selectedAsset: WallpaperAssetRecord?
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let modelContext: ModelContext

    var body: some ToolbarContent {
        ToolbarItemGroup {
            ResolutionToolbarMenu(
                asset: selectedAsset,
                assets: assets,
                profiles: profiles,
                modelContext: modelContext
            )

            Button {
                appState.toggleManualPause()
            } label: {
                Label(appState.isManuallyPaused ? "Resume" : "Pause", systemImage: appState.isManuallyPaused ? "play.fill" : "pause.fill")
            }

            Toggle(isOn: $appState.isEditModeEnabled) {
                Label("Edit Wallpaper", systemImage: "slider.horizontal.3")
            }
            .toggleStyle(.button)

            Button {
                columnVisibility = columnVisibility == .all ? .doubleColumn : .all
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

private struct ResolutionToolbarMenu: View {
    @EnvironmentObject private var appState: AppState

    let asset: WallpaperAssetRecord?
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]
    let modelContext: ModelContext

    var body: some View {
        Menu {
            Button("Auto / Native") {
                setResolution(.auto)
            }
            Button("4K (3840x2160)") {
                setResolution(.fourK)
            }
            Button("1440p (2560x1440)") {
                setResolution(.qhd1440p)
            }
            Button("1080p (1920x1080)") {
                setResolution(.fhd1080p)
            }

            Menu("Custom Aspect") {
                Button("16:9") {
                    setResolution(WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 16, customAspectHeight: 9))
                }
                Button("16:10") {
                    setResolution(WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 16, customAspectHeight: 10))
                }
                Button("21:9") {
                    setResolution(WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 21, customAspectHeight: 9))
                }
                Button("4:3") {
                    setResolution(WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 4, customAspectHeight: 3))
                }
                Button("1:1") {
                    setResolution(WallpaperCanvasResolution(mode: .customAspect, customAspectWidth: 1, customAspectHeight: 1))
                }
            }
        } label: {
            Label(asset?.editorConfiguration.canvasResolution.displayTitle ?? "Resolution", systemImage: "aspectratio")
        }
        .disabled(asset == nil)
        .help("Wallpaper output canvas resolution")
    }

    private func setResolution(_ resolution: WallpaperCanvasResolution) {
        guard let asset else { return }
        appState.updateEditorConfiguration(for: asset, assets: assets, profiles: profiles, modelContext: modelContext) { configuration in
            configuration.canvasResolution = resolution
        }
    }
}
