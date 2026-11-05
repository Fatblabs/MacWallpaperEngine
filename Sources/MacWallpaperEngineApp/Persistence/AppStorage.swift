import Foundation
import CryptoKit

enum AppStorage {
    // Explicit isolation also works for packaged-app smoke tests, without changing HOME.
    static let root: URL = {
        if let path = ProcessInfo.processInfo.environment["MACWALLPAPERENGINE_DATA_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") }) {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MacWallpaperEngine-tests-\(ProcessInfo.processInfo.processIdentifier)")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacWallpaperEngine", isDirectory: true)
    }()

    @MainActor static let defaults: UserDefaults = {
        if ProcessInfo.processInfo.environment["MACWALLPAPERENGINE_DATA_DIRECTORY"] != nil ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") }) {
            let identifier = SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            return UserDefaults(suiteName: "MacWallpaperEngine.isolated.\(identifier)")!
        }
        return .standard
    }()
}
