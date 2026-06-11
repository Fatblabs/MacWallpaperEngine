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
        WindowGroup("MacWallpaperEngine") {
            ContentView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
                .frame(minWidth: 1_060, minHeight: 660)
                .task {
                    appState.bootstrapFromStore(modelContext: modelContainer.mainContext)
                }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("MacWallpaperEngine", systemImage: "play.rectangle.on.rectangle") {
            MenuBarView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }

    private static func modelStoreURL() throws -> URL {
        let supportDirectory = applicationSupportDirectory()
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let storeURL = supportDirectory.appendingPathComponent("MacWallpaperEngine.store")
        migrateLegacyDefaultStoreIfNeeded(to: storeURL)
        return storeURL
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL.appendingPathComponent("MacWallpaperEngine", isDirectory: true)
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
