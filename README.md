# MacWallpaperEngine

A native, local-video-only wallpaper engine for macOS.

The v1 implementation focuses on the important bits first:

- local MP4/MOV/M4V and other QuickTime-playable video imports
- drag-and-drop and Finder file picker import
- one wallpaper window per display
- AVFoundation playback for low overhead
- intelligent pausing for covered desktops, full-screen apps, battery, Low Power Mode, and thermal pressure
- menu bar controls plus a SwiftUI settings window
- a wallpaper creator for trimming long videos, tuning color, changing playback speed, toggling composition layers, adding text, and configuring clock/calendar widgets
- light/dark and time-of-day wallpaper variant switching

## Wallpaper Creator

Open the app, choose the **Editor** tab, and select an imported wallpaper. The editor stores settings per wallpaper:

- videos 60 seconds or longer get a dual-handle snippet slider with precise start/end steppers
- hue, saturation, brightness, contrast, blur, and icon-readability tint
- playback speed from calm slow loops to faster animation
- component toggles for the video layer, ambient fog, moving clouds, foreground vignette, custom text, and widgets
- cursor-follow particles, parallax depth, and click reactions
- custom text using installed macOS fonts
- clock/calendar widgets with 12h/24h format, font, alignment, and position controls
- system Light/Dark or exact time-of-day wallpaper variants

## Build

Open `Package.swift` in Xcode, or build from Terminal:

```sh
swift build
swift test
```

Run the app executable:

```sh
swift run MacWallpaperEngine
```

The current package is a developer-friendly SwiftPM app scaffold. A signed/notarized `.app` packaging target should be added before public distribution.
