import SwiftUI

struct DualHandleRangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double

    let bounds: ClosedRange<Double>
    var minimumDistance: Double = 0.5

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let centerY = proxy.size.height / 2
            let lowerX = xPosition(for: lowerValue, width: width)
            let upperX = xPosition(for: upperValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(height: 5)
                    .position(x: width / 2, y: centerY)

                Capsule()
                    .fill(.blue)
                    .frame(width: max(0, upperX - lowerX), height: 5)
                    .position(x: lowerX + max(0, upperX - lowerX) / 2, y: centerY)

                sliderHandle
                    .position(x: lowerX, y: centerY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let proposed = valueFor(x: value.location.x, width: width)
                                lowerValue = min(max(bounds.lowerBound, proposed), upperValue - minimumDistance)
                            }
                    )

                sliderHandle
                    .position(x: upperX, y: centerY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let proposed = valueFor(x: value.location.x, width: width)
                                upperValue = max(min(bounds.upperBound, proposed), lowerValue + minimumDistance)
                            }
                    )
            }
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wallpaper snippet range")
        .accessibilityValue("\(formatted(lowerValue)) to \(formatted(upperValue))")
    }

    private var sliderHandle: some View {
        Circle()
            .fill(.white)
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
            .overlay(Circle().stroke(.blue, lineWidth: 2))
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        let ratio = (clamped - bounds.lowerBound) / max(0.0001, bounds.upperBound - bounds.lowerBound)
        return CGFloat(ratio) * width
    }

    private func valueFor(x: CGFloat, width: CGFloat) -> Double {
        let ratio = min(max(0, Double(x / width)), 1)
        return bounds.lowerBound + ratio * (bounds.upperBound - bounds.lowerBound)
    }

    private func formatted(_ value: Double) -> String {
        let totalSeconds = Int(value.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
