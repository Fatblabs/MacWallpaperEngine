import Foundation
import SwiftData
import SwiftUI

@main
struct MacWallpaperEngineApp: App {
    @StateObject private var appState = AppState()

    private let modelContainer: ModelContainer = {
        do {
            let configuration = ModelConfiguration(url: try modelStoreURL())
            return try ModelContainer(
                for: WallpaperAssetRecord.self,
                DisplayProfileRecord.self,
                AppSettingsRecord.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        Window("MacWallpaperEngine", id: "library") {
            ContentView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
                .frame(minWidth: 1_060, minHeight: 660)
                .task {
                    appState.bootstrapFromStore(modelContext: modelContainer.mainContext)
                }
                .onOpenURL { appState.importVideo($0, modelContext: modelContainer.mainContext) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.stop()
                }
        }
        Settings {
            SettingsView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
        }

        MenuBarExtra("MacWallpaperEngine", systemImage: "play.rectangle.on.rectangle") {
            MenuBarView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }

    private static func modelStoreURL() throws -> URL {
        let supportDirectory = AppStorage.root
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let storeURL = supportDirectory.appendingPathComponent("MacWallpaperEngine.store")
        if ProcessInfo.processInfo.environment["MACWALLPAPERENGINE_DATA_DIRECTORY"] == nil {
            migrateLegacyDefaultStoreIfNeeded(to: storeURL)
        }
        return storeURL
    }

    private static func migrateLegacyDefaultStoreIfNeeded(to storeURL: URL) {
        guard !FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let legacyBaseURL = storeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: legacyBaseURL.path) else { return }

        for suffix in ["", "-shm", "-wal"] {
            let sourceURL = URL(fileURLWithPath: legacyBaseURL.path + suffix)
            let destinationURL = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceURL.path),
                  !FileManager.default.fileExists(atPath: destinationURL.path) else {
                continue
            }
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
