import MacWallpaperEngineCore
import SwiftUI

struct FPSCapControl: View {
    let title: String
    @Binding var fps: Int
    var allowsNative: Bool = false

    @State private var typedValue = ""

    private let presets = [0, 15, 24, 30, 60, 90, 120, 144, 165, 240, 360, 500]

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
                    ForEach(presets.filter { allowsNative || $0 > 0 }, id: \.self) { preset in
                        if preset > 0 {
                            Text("\(preset) fps").tag(preset)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                Button {
                    fps = sanitized(fps - 1)
                    typedValue = displayValue
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)

                TextField("FPS", text: $typedValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onAppear {
                        typedValue = displayValue
                    }
                    .onSubmit {
                        fps = sanitized(Int(typedValue) ?? fps)
                        typedValue = displayValue
                    }
                    .onChange(of: typedValue) {
                        guard let value = Int(typedValue) else { return }
                        fps = sanitized(value)
                    }
                    .monospacedDigit()

                Button {
                    fps = sanitized(fps + 1)
                    typedValue = displayValue
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)

                Text(fps == 0 ? "Native" : "fps")
                    .foregroundStyle(.secondary)
            }
        }
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
