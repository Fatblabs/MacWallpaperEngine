# MacWallpaperEngine

A native, local-video-only wallpaper engine for macOS.

The v1 implementation focuses on the important bits first:

- local MP4/MOV/M4V and other QuickTime-playable video imports
- drag-and-drop and Finder file picker import
- visible wallpaper removal beside the Library add button and from the library context menu
- toolbar canvas resolution presets for Auto/Native, 4K, 1440p, 1080p, and custom aspect ratios
- one wallpaper window per display
- AVFoundation playback for low overhead
- intelligent pausing for covered desktops, full-screen apps, battery, Low Power Mode, and thermal pressure
- menu bar controls plus a SwiftUI settings window
- a wallpaper creator for trimming long videos, tuning color, changing playback speed, toggling composition layers, adding text, and configuring clock/calendar widgets
- a unified three-panel editor: library sidebar, adaptive live-preview canvas with contextual lower pane, and Canva-like modular inspector
- playlist ordering with AVQueuePlayer-backed playback and crossfade transition composition
- modular widget runtime for Clock, Hardware Monitor, and Weather modules that can load, update, swap, and unload without restarting wallpaper playback
- light/dark and time-of-day wallpaper variant switching
- pinned Application Support SwiftData store plus restore snapshot, mirrored to UserDefaults, with bookmarks, editor settings, display assignments, immediate background window setup, and alpha-fade video restoration

## Wallpaper Creator

Open the app and select an imported wallpaper in the left library. The center pane shows an adaptive live preview on top and a contextual workspace below, while the right inspector uses a thin icon dock for focused modules:

- videos 60 seconds or longer get a dual-handle snippet slider capped to a 30-60 second optimized range
- optimized snippets can be exported locally with AVFoundation
- multi-video wallpapers switch the lower pane into a drag-and-drop playlist order editor
- Layers keeps component toggles, playlist/widget layer controls, and playback speed together
- Text isolates custom text and clock/calendar typography controls
- Effects contains color tuning, blur, tint, and interaction controls
- Settings contains power policy and theme sync without duplicating add/remove actions
- Clock, Hardware Monitor, and Weather widgets use one serialized schema with position, anchor locking, style, opacity, and refresh interval
- selecting a widget changes the inspector instantly to that widget's specific controls
- system Light/Dark or exact time-of-day wallpaper variants

## Running A Build

The current debug executable is produced by SwiftPM at:

```text
.build/arm64-apple-macosx/debug/MacWallpaperEngine
```

Run it with:

```sh
swift run MacWallpaperEngine
```

For users without a Developer ID, the next packaging step is an unsigned `.app` bundle plus zip. They can run it locally with a Gatekeeper override, but public distribution should use Developer ID signing and notarization.

Create the unsigned local app bundle and zip with:

```sh
scripts/package-unsigned-app.sh
```

That produces:

```text
dist/MacWallpaperEngine.app
dist/MacWallpaperEngine-unsigned.zip
```

## Source Layout

The SwiftPM targets are organized by ownership:

- `Sources/MacWallpaperEngineApp/App`: app entry point and scene setup
- `Sources/MacWallpaperEngineApp/State`: app orchestration and launch restore flow
- `Sources/MacWallpaperEngineApp/Persistence`: SwiftData records and restore cache
- `Sources/MacWallpaperEngineApp/Rendering`: desktop windows, playback, display layout, and playlist composition
- `Sources/MacWallpaperEngineApp/UI`: editor, menu bar, and reusable SwiftUI controls
- `Sources/MacWallpaperEngineApp/System`: power, coverage, and launch-at-login integration
- `Sources/MacWallpaperEngineApp/Widgets`: widget runtime and overlay configuration
- `Sources/MacWallpaperEngineCore`: platform-light models, policies, and geometry helpers

## Build

Open `Package.swift` in Xcode, or build from Terminal:

```sh
swift build
swift test
```

The current package is a developer-friendly SwiftPM app scaffold. A signed/notarized `.app` packaging target should be added before public distribution.
