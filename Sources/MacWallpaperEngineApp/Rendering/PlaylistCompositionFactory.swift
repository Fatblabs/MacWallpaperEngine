import AVFoundation
import CoreGraphics
import Foundation

@MainActor
enum PlaylistCompositionFactory {
    static func playerItem(
        currentURL: URL,
        nextURL: URL?,
        crossfadeDuration: Double,
        preferredBufferSeconds: Double = 5
    ) -> AVPlayerItem {
        guard let nextURL,
              crossfadeDuration > 0,
              let transitionItem = transitionItem(
                currentURL: currentURL,
                nextURL: nextURL,
                crossfadeDuration: crossfadeDuration
              ) else {
            let item = AVPlayerItem(asset: AVURLAsset(url: currentURL))
            item.preferredForwardBufferDuration = preferredBufferSeconds
            return item
        }

        transitionItem.preferredForwardBufferDuration = preferredBufferSeconds
        return transitionItem
    }

    private static func transitionItem(
        currentURL: URL,
        nextURL: URL,
        crossfadeDuration: Double
    ) -> AVPlayerItem? {
        let currentAsset = AVURLAsset(url: currentURL)
        let nextAsset = AVURLAsset(url: nextURL)

        guard let currentTrack = currentAsset.tracks(withMediaType: .video).first,
              let nextTrack = nextAsset.tracks(withMediaType: .video).first else {
            return nil
        }

        let currentDuration = currentAsset.duration
        guard currentDuration.seconds.isFinite, currentDuration.seconds > 0.5 else {
            return nil
        }

        let fadeDuration = CMTime(
            seconds: min(crossfadeDuration, max(0.25, currentDuration.seconds / 3)),
            preferredTimescale: 600
        )
        let fadeStart = CMTimeSubtract(currentDuration, fadeDuration)

        let composition = AVMutableComposition()
        guard let baseTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
              let overlayTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }

        do {
            try baseTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: currentDuration),
                of: currentTrack,
                at: .zero
            )
            try overlayTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: fadeDuration),
                of: nextTrack,
                at: fadeStart
            )
            baseTrack.preferredTransform = currentTrack.preferredTransform
            overlayTrack.preferredTransform = nextTrack.preferredTransform
        } catch {
            return nil
        }

        let renderSize = positiveRenderSize(for: currentTrack)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let beforeInstruction = AVMutableVideoCompositionInstruction()
        beforeInstruction.timeRange = CMTimeRange(start: .zero, end: fadeStart)
        let beforeLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
        beforeLayer.setTransform(currentTrack.preferredTransform, at: .zero)
        beforeInstruction.layerInstructions = [beforeLayer]

        let fadeInstruction = AVMutableVideoCompositionInstruction()
        fadeInstruction.timeRange = CMTimeRange(start: fadeStart, duration: fadeDuration)
        let fadeOutLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
        fadeOutLayer.setTransform(currentTrack.preferredTransform, at: fadeStart)
        fadeOutLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: fadeInstruction.timeRange)
        let fadeInLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: overlayTrack)
        fadeInLayer.setTransform(nextTrack.preferredTransform, at: fadeStart)
        fadeInLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: fadeInstruction.timeRange)
        fadeInstruction.layerInstructions = [fadeInLayer, fadeOutLayer]

        videoComposition.instructions = [beforeInstruction, fadeInstruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }

    private static func positiveRenderSize(for track: AVAssetTrack) -> CGSize {
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: max(1, abs(transformedSize.width)), height: max(1, abs(transformedSize.height)))
    }
}
