import SwiftData
import SwiftUI

struct DisplaySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let assets: [WallpaperAssetRecord]
    let profiles: [DisplayProfileRecord]

    private var displays: [WallpaperDisplay] {
        WallpaperDisplay.displays()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Displays")
                    .font(.largeTitle.weight(.semibold))
                Text("Assign one video everywhere, or tune each monitor separately.")
                    .foregroundStyle(.secondary)
            }

            if assets.isEmpty {
                ContentUnavailableView(
                    "No Videos Yet",
                    systemImage: "display",
                    description: Text("Import a local video before assigning wallpapers to displays.")
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(displays) { display in
                        DisplayRow(
                            display: display,
                            assets: assets,
                            profile: profiles.first { $0.screenID == display.idString }
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

private struct DisplayRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let display: WallpaperDisplay
    let assets: [WallpaperAssetRecord]
    let profile: DisplayProfileRecord?

    private var selectedAssetID: UUID? {
        profile?.assignedAssetID ?? assets.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.headline)
                    Text("\(Int(display.frame.width))x\(Int(display.frame.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Wallpaper", selection: Binding(
                    get: { selectedAssetID },
                    set: { id in
                        guard let id, let asset = assets.first(where: { $0.id == id }) else { return }
                        appState.setAsset(asset, for: display, modelContext: modelContext)
                    }
                )) {
                    ForEach(assets) { asset in
                        Text(asset.displayName).tag(Optional(asset.id))
                    }
                }
                .frame(width: 260)
            }

            Picker("Layout", selection: Binding(
                get: { profile?.layoutMode ?? .fill },
                set: { layout in
                    appState.setLayout(layout, for: display, modelContext: modelContext)
                }
            )) {
                ForEach(WallpaperLayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
