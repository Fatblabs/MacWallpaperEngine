import AVFoundation
import Darwin
import Foundation
@testable import MacWallpaperEngineCore
import Testing

@Suite("LocalVideoImporter")
struct LocalVideoImporterTests {
    @Test
    func rejectsRemoteURLs() {
        let url = URL(string: "https://example.com/wallpaper.mp4")!
        #expect(LocalVideoImporter.isSupportedLocalVideoURL(url) == false)
    }

    @Test
    func acceptsPreferredLocalMovieExtensions() {
        #expect(LocalVideoImporter.isSupportedLocalVideoURL(URL(fileURLWithPath: "/tmp/test.mp4")))
        #expect(LocalVideoImporter.isSupportedLocalVideoURL(URL(fileURLWithPath: "/tmp/test.mov")))
        #expect(LocalVideoImporter.isSupportedLocalVideoURL(URL(fileURLWithPath: "/tmp/test.m4v")))
    }

    @Test
    func rejectsUnsupportedExtensions() {
        #expect(LocalVideoImporter.isSupportedLocalVideoURL(URL(fileURLWithPath: "/tmp/test.txt")) == false)
    }

    @Test
    func readsMetadataFromGeneratedLocalMovie() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try await Self.writeTestMovie(to: url)
        let metadata = try await LocalVideoImporter.metadata(for: url)

        #expect(metadata.displayName == url.deletingPathExtension().lastPathComponent)
        #expect(metadata.pixelWidth == 16)
        #expect(metadata.pixelHeight == 16)
        #expect(metadata.duration >= 0)
        #expect(metadata.bookmarkData.isEmpty == false)
    }

    private static func writeTestMovie(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
        )

        guard writer.canAdd(input) else {
            throw TestMovieError.cannotAddInput
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(10))
        }

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw TestMovieError.missingPixelBufferPool
        }

        let firstFrame = try makePixelBuffer(from: pixelBufferPool, fill: 0x44)
        let secondFrame = try makePixelBuffer(from: pixelBufferPool, fill: 0x88)
        adaptor.append(firstFrame, withPresentationTime: .zero)
        adaptor.append(secondFrame, withPresentationTime: CMTime(seconds: 1, preferredTimescale: 600))
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
