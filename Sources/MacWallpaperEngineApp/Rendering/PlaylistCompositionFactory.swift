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
    ) async -> AVPlayerItem {
        guard let nextURL,
              crossfadeDuration > 0,
              let transitionItem = await transitionItem(
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
    ) async -> AVPlayerItem? {
        let currentAsset = AVURLAsset(url: currentURL)
        let nextAsset = AVURLAsset(url: nextURL)

        guard let currentTrack = try? await currentAsset.loadTracks(withMediaType: .video).first,
              let nextTrack = try? await nextAsset.loadTracks(withMediaType: .video).first,
              let currentDuration = try? await currentAsset.load(.duration),
              let currentTransform = try? await currentTrack.load(.preferredTransform),
              let nextTransform = try? await nextTrack.load(.preferredTransform) else {
            return nil
        }

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
            baseTrack.preferredTransform = currentTransform
            overlayTrack.preferredTransform = nextTransform
        } catch {
            return nil
        }

        guard let renderSize = try? await positiveRenderSize(for: currentTrack, transform: currentTransform) else {
            return nil
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let beforeInstruction = AVMutableVideoCompositionInstruction()
        beforeInstruction.timeRange = CMTimeRange(start: .zero, end: fadeStart)
        let beforeLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
        beforeLayer.setTransform(currentTransform, at: .zero)
        beforeInstruction.layerInstructions = [beforeLayer]

        let fadeInstruction = AVMutableVideoCompositionInstruction()
        fadeInstruction.timeRange = CMTimeRange(start: fadeStart, duration: fadeDuration)
        let fadeOutLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
        fadeOutLayer.setTransform(currentTransform, at: fadeStart)
        fadeOutLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: fadeInstruction.timeRange)
        let fadeInLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: overlayTrack)
        fadeInLayer.setTransform(nextTransform, at: fadeStart)
        fadeInLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: fadeInstruction.timeRange)
        fadeInstruction.layerInstructions = [fadeInLayer, fadeOutLayer]

        videoComposition.instructions = [beforeInstruction, fadeInstruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }

    private static func positiveRenderSize(for track: AVAssetTrack, transform: CGAffineTransform) async throws -> CGSize {
        let transformedSize = try await track.load(.naturalSize).applying(transform)
        return CGSize(width: max(1, abs(transformedSize.width)), height: max(1, abs(transformedSize.height)))
    }
}
