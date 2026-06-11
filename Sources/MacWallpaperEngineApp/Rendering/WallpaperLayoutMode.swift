import AVFoundation

enum WallpaperLayoutMode: String, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill:
            "Fill"
        case .fit:
            "Fit"
        case .stretch:
            "Stretch"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            .resizeAspectFill
        case .fit:
            .resizeAspect
        case .stretch:
            .resize
        }
    }
}
