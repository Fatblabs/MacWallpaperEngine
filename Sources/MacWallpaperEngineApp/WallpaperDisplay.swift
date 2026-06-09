import AppKit
import CoreGraphics
import MacWallpaperEngineCore

struct WallpaperDisplay: Identifiable, Hashable {
    var id: UInt32
    var name: String
    var frame: CGRect
    var screen: NSScreen

    var idString: String {
        String(id)
    }

    static func displays() -> [WallpaperDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return WallpaperDisplay(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                screen: screen
            )
        }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return number.uint32Value
    }
}

struct WallpaperDisplayConfiguration {
    var display: WallpaperDisplay
    var assetID: UUID?
    var fileURL: URL?
    var assetDuration: Double
    var layoutMode: WallpaperLayoutMode
    var editorConfiguration: WallpaperEditorConfiguration
}
