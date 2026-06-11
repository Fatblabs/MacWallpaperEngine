import AVFoundation
import Darwin
import Foundation
@testable import MacWallpaperEngineApp
@testable import MacWallpaperEngineCore
import Testing

@Suite("SmoothVideoExporter")
struct SmoothVideoExporterTests {
    @Test
    func exportsGeneratedSmoothCopyThatReimportsAsLocalVideo() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        try await Self.writeTestMovie(to: sourceURL)

        let outputURL = try await SmoothVideoExporter.exportSmoothCopy(
            sourceURL: sourceURL,
            assetID: UUID(),
            sourceDisplayName: "Smoke Test",
            preset: SmoothVideoExportPreset(title: "60 FPS Smoke", targetFPS: 60, interpolationMode: .blend)
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let metadata = try await LocalVideoImporter.metadata(for: outputURL)
        #expect(metadata.pixelWidth == 128)
        #expect(metadata.pixelHeight == 72)
        #expect(metadata.duration > 0)

        let outputAsset = AVURLAsset(url: outputURL)
        let outputTrack = try #require(try await outputAsset.loadTracks(withMediaType: .video).first)
        let outputFPS = try await outputTrack.load(.nominalFrameRate)
        #expect(outputFPS >= 50)
    }

    @Test
    func exportsMotionPredictionCopyThatReimportsAsLocalVideo() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        try await Self.writeTestMovie(to: sourceURL)

        let outputURL = try await SmoothVideoExporter.exportSmoothCopy(
            sourceURL: sourceURL,
            assetID: UUID(),
            sourceDisplayName: "Motion Prediction Smoke Test",
            preset: SmoothVideoExportPreset(title: "60 FPS Motion", targetFPS: 60, interpolationMode: .opticalFlow)
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let metadata = try await LocalVideoImporter.metadata(for: outputURL)
        #expect(metadata.pixelWidth == 128)
        #expect(metadata.pixelHeight == 72)
        #expect(metadata.duration > 0)
    }

    private static func writeTestMovie(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 72
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 128,
                kCVPixelBufferHeightKey as String: 72
            ]
        )

        guard writer.canAdd(input) else {
            throw TestMovieError.cannotAddInput
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw TestMovieError.missingPixelBufferPool
        }

        for frameIndex in 0..<4 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }

            let frame = try makePixelBuffer(from: pixelBufferPool, fill: Int32(0x44 + frameIndex * 0x18))
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: 30)
            adaptor.append(frame, withPresentationTime: presentationTime)
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed || writer.status == .cancelled {
            throw writer.error ?? TestMovieError.writerFailed
        }
    }

    private static func makePixelBuffer(from pool: CVPixelBufferPool, fill: Int32) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestMovieError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, fill, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    private enum TestMovieError: Error {
        case cannotAddInput
        case missingPixelBufferPool
        case pixelBufferCreationFailed
        case writerFailed
    }
}
