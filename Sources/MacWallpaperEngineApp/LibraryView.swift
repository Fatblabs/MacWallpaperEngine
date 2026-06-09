import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let assets: [WallpaperAssetRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.largeTitle.weight(.semibold))
                    Text("Local videos only. Drag in a movie or choose one from Finder.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.chooseVideo(modelContext: modelContext)
                } label: {
                    Label("Choose Video...", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = appState.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if assets.isEmpty {
                EmptyLibraryView()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(assets) { asset in
                            AssetCard(asset: asset)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(24)
    }
}

private struct EmptyLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            Text("Start with one local video")
                .font(.title2.weight(.semibold))

            Text("MP4, MOV, M4V, and QuickTime-playable movie files are supported. Nothing is uploaded.")
                .foregroundStyle(.secondary)

            Button {
                appState.chooseVideo(modelContext: modelContext)
            } label: {
                Label("Choose Video...", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AssetCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let asset: WallpaperAssetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if let image = PosterFrameCache.image(for: asset.posterFrameFilename) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.linearGradient(colors: [.blue.opacity(0.35), .black.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(asset.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Text(asset.aspectDescription)
                    Text(asset.codecSummary)
                    Text(formattedDuration(asset.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Set All Displays") {
                    appState.setAsset(asset, for: nil, modelContext: modelContext)
                }

                Spacer()

                if FileManager.default.fileExists(atPath: asset.lastKnownPath) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Moved", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func formattedDuration(_ duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return "Unknown" }
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
    }
}
