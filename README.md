# MacWallpaperEngine

A native, local-video-only wallpaper engine for macOS.

The v1 implementation focuses on the important bits first:

- local MP4/MOV/M4V and other QuickTime-playable video imports
- drag-and-drop and Finder file picker import
- visible wallpaper removal from the library context menu and inspector
- one wallpaper window per display
- AVFoundation playback for low overhead
- intelligent pausing for covered desktops, full-screen apps, battery, Low Power Mode, and thermal pressure
- menu bar controls plus a SwiftUI settings window
- a wallpaper creator for trimming long videos, tuning color, changing playback speed, toggling composition layers, adding text, and configuring clock/calendar widgets
- a unified three-panel editor: library sidebar, live-preview canvas with contextual lower pane, and collapsible inspector
- playlist ordering with AVQueuePlayer-backed playback and crossfade transition composition
- modular widget runtime for Clock, Hardware Monitor, and Weather modules that can load, update, swap, and unload without restarting wallpaper playback
- light/dark and time-of-day wallpaper variant switching
- UserDefaults-backed restoration snapshot for the last active wallpapers and display assignments, with immediate background window setup and alpha-fade video restoration

## Wallpaper Creator

Open the app and select an imported wallpaper in the left library. The center pane shows a live preview on top and a contextual workspace below, while the right inspector holds all customization controls:

- videos 60 seconds or longer get a dual-handle snippet slider capped to a 30-60 second optimized range
- optimized snippets can be exported locally with AVFoundation
- multi-video wallpapers switch the lower pane into a drag-and-drop playlist order editor
- hue, saturation, brightness, contrast, blur, and icon-readability tint
- playback speed from calm slow loops to faster animation
- component toggles for the video layer, ambient fog, moving clouds, foreground vignette, custom text, and widgets
- cursor-follow particles, parallax depth, and click reactions
- custom text using installed macOS fonts
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

## Build

Open `Package.swift` in Xcode, or build from Terminal:

```sh
swift build
swift test
```

The current package is a developer-friendly SwiftPM app scaffold. A signed/notarized `.app` packaging target should be added before public distribution.
