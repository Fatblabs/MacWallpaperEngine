import MacWallpaperEngineCore
import SwiftData
import SwiftUI

struct WidgetsView: View {
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

        return assets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Widgets")
                    .font(.largeTitle.weight(.semibold))
                Text("Widgets are fused into each wallpaper, so text, clock, and calendar settings travel with the video.")
                    .foregroundStyle(.secondary)
            }

            if assets.isEmpty {
                ContentUnavailableView(
                    "No Wallpaper Selected",
                    systemImage: "clock.badge",
                    description: Text("Import a video before adding wallpaper widgets.")
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
                        ClockCalendarEditorSection(configuration: configurationBinding(for: selectedAsset))
                        TextEditorSection(configuration: configurationBinding(for: selectedAsset))
                        EditorSectionCard(title: "Future Widgets") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                                WidgetTemplateCard(title: "Battery", subtitle: "Already supported in the menu; desktop meter next", systemImage: "battery.75")
                                WidgetTemplateCard(title: "CPU", subtitle: "Coming after performance profiling", systemImage: "cpu")
                                WidgetTemplateCard(title: "Weather", subtitle: "Requires explicit setup", systemImage: "cloud.sun")
                            }
                        }
                    }
                    .padding(.bottom, 28)
                }
            }

            Toggle(isOn: $appState.isEditModeEnabled) {
                Label("Edit Wallpaper Mode", systemImage: "slider.horizontal.3")
            }
            .toggleStyle(.button)

            Spacer()
        }
        .padding(24)
        .onAppear {
            selectedAssetID = selectedAsset?.id
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

private struct WidgetTemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.blue)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.caption)

            Button("Add Widget") {}
                .disabled(true)
                .help("This widget ships after the core playback engine is stable.")
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
