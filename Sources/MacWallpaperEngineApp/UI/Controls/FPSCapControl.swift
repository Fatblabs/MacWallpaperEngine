import MacWallpaperEngineCore
import SwiftUI

struct FPSCapControl: View {
    let title: String
    @Binding var fps: Int
    var allowsNative: Bool = false

    @State private var typedValue = ""
    @FocusState private var isEditing: Bool

    private static let presets = [0, 15, 24, 30, 60, 90, 120, 144, 165, 240, 360, 500]
    private static let positivePresets = presets.filter { $0 > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { fps },
                    set: { newValue in
                        fps = sanitized(newValue)
                        typedValue = displayValue
                    }
                )) {
                    if allowsNative {
                        Text("Native").tag(0)
                    }
                    if !Self.presets.contains(fps) {
                        Text("\(fps) fps").tag(fps)
                    }
                    ForEach(allowsNative ? Self.presets : Self.positivePresets, id: \.self) { preset in
                        if preset > 0 {
                            Text("\(preset) fps").tag(preset)
                        }
                    }
                }
                .labelsHidden()
                .frame(minWidth: 100, maxWidth: .infinity)

                TextField("FPS", text: $typedValue)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 56)
                    .focused($isEditing)
                    .accessibilityLabel("\(title) custom cap")
                    .onAppear {
                        typedValue = displayValue
                    }
                    .onSubmit {
                        commit()
                    }
                    .onChange(of: isEditing) {
                        if !isEditing { commit() }
                    }
                    .onChange(of: fps) {
                        if !isEditing { typedValue = displayValue }
                    }
                    .monospacedDigit()

                Stepper(title, value: $fps, in: (allowsNative ? 0 : 1)...PlaybackFrameRateCap.maximumSupportedFPS)
                    .labelsHidden()
                    .help("Adjust \(title)")
            }
        }
    }

    private func commit() {
        fps = sanitized(typedValue.isEmpty && allowsNative ? 0 : (Int(typedValue) ?? fps))
        typedValue = displayValue
    }

    private var displayValue: String {
        fps == 0 ? "" : "\(fps)"
    }

    private func sanitized(_ value: Int) -> Int {
        if allowsNative, value <= 0 {
            return 0
        }

        return PlaybackFrameRateCap.clampedTargetFPS(value)
    }
}
