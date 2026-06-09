import MacWallpaperEngineCore
import SwiftUI

struct PerformanceSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Pause when covered", isOn: $appState.policy.pauseWhenCovered)
                Toggle("Pause during full-screen apps", isOn: $appState.policy.pauseDuringFullscreenApps)
                Toggle("Reduce on battery", isOn: $appState.policy.reduceOnBattery)
                Toggle("Pause when Mac is hot", isOn: $appState.policy.pauseWhenHot)
            } header: {
                Text("Intelligent Pausing")
            } footer: {
                Text("Coverage checks run around twice per second to keep window-server work low.")
            }

            Section("Thresholds") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Desktop coverage")
                        Spacer()
                        Text("\(Int(appState.policy.coverageThreshold * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.policy.coverageThreshold, in: 0.5...1.0, step: 0.05)
                }

                Stepper(value: $appState.policy.batteryFPSCap, in: 1...60) {
                    Text("Battery cap: \(appState.policy.batteryFPSCap) fps")
                }

                Picker("Normal FPS cap", selection: Binding(
                    get: { appState.policy.normalFPSCap ?? 0 },
                    set: { value in
                        appState.policy.normalFPSCap = value == 0 ? nil : value
                    }
                )) {
                    Text("Native").tag(0)
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                    Text("24 fps").tag(24)
                    Text("15 fps").tag(15)
                }
            }

            Section("Current Status") {
                LabeledContent("Mode", value: modeDescription(appState.playbackMode))
                LabeledContent("Message", value: appState.statusMessage)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private func modeDescription(_ mode: PlaybackMode) -> String {
        switch mode {
        case .full:
            "Full"
        case .capped(let fps):
            "Capped at \(fps) fps"
        case .posterFrame(let reason):
            "Poster frame (\(reason.rawValue))"
        case .paused(let reason):
            "Paused (\(reason.rawValue))"
        }
    }
}
