import SwiftData
import SwiftUI

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \WallpaperAssetRecord.createdAt, order: .reverse) private var assets: [WallpaperAssetRecord]
    @Query private var profiles: [DisplayProfileRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacWallpaperEngine")
                        .font(.headline)
                    Text(appState.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.toggleManualPause()
                } label: {
                    Image(systemName: appState.isManuallyPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button {
                appState.chooseVideo(modelContext: modelContext)
            } label: {
                Label("Choose Video...", systemImage: "folder")
            }

            if let firstAsset = assets.first {
                Button {
                    appState.setAsset(firstAsset, for: nil, modelContext: modelContext)
                    appState.reconcile(assets: assets, profiles: profiles)
                } label: {
                    Label("Set Latest on All Displays", systemImage: "display.2")
                }
            }

            Toggle(isOn: $appState.policy.reduceOnBattery) {
                Text("Reduce on Battery")
            }

            Toggle(isOn: $appState.isEditModeEnabled) {
                Text("Edit Wallpaper")
            }

            Divider()

            Button("Open Settings") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            appState.reconcile(assets: assets, profiles: profiles)
        }
    }
}
