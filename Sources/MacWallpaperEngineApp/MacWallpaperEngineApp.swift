import SwiftData
import SwiftUI

@main
struct MacWallpaperEngineApp: App {
    @StateObject private var appState = AppState()

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: WallpaperAssetRecord.self,
                DisplayProfileRecord.self,
                AppSettingsRecord.self
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
                .frame(minWidth: 920, minHeight: 620)
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
}
