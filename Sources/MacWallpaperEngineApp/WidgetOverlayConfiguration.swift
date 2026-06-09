import Foundation

enum WidgetOverlayPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft:
            "Top Left"
        case .topRight:
            "Top Right"
        case .bottomLeft:
            "Bottom Left"
        case .bottomRight:
            "Bottom Right"
        }
    }
}

struct WidgetOverlayConfiguration: Codable, Equatable {
    var showClock: Bool = false
    var showDate: Bool = false
    var showBattery: Bool = false
    var position: WidgetOverlayPosition = .topRight

    var isEnabled: Bool {
        showClock || showDate || showBattery
    }
}
