import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MacWallpaperEngineCore
import Metal
import MetalKit
import Vision

enum SmoothVideoExporter {
    static func exportSmoothCopy(
        sourceURL: URL,
        assetID: UUID,
        sourceDisplayName: String,
        preset: SmoothVideoExportPreset
    ) async throws -> URL {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let duration = CMTimeGetSeconds(try await sourceAsset.load(.duration))
        guard duration.isFinite, duration > 0 else {
            throw ExportError.unreadableDuration
        }

        let sourceSize = try await sourceDimensions(for: videoTrack)
        let outputSize = preset.outputDimensions(sourceWidth: sourceSize.width, sourceHeight: sourceSize.height)
        let targetFPS = preset.normalizedTargetFPS
        let sourceFPS = sanitizedFrameRate(try await videoTrack.load(.nominalFrameRate))
        let outputURL = try generatedOutputURL(
            assetID: assetID,
            sourceDisplayName: sourceDisplayName,
            preset: preset,
            outputSize: outputSize
        )

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: outputSettings(outputSize: outputSize, targetFPS: targetFPS)
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else {
            throw ExportError.cannotAddVideoInput
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? ExportError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)

        let imageGenerator = AVAssetImageGenerator(asset: sourceAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        let sourceFrameDuration = CMTime(seconds: 1 / sourceFPS, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceBefore = sourceFrameDuration
        imageGenerator.requestedTimeToleranceAfter = sourceFrameDuration

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw ExportError.missingPixelBufferPool
        }

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw ExportError.missingMetalDevice
        }

        let ciContext = CIContext(mtlDevice: metalDevice, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        let opticalFlowInterpolator = try? MetalOpticalFlowInterpolator(device: metalDevice)
        let outputBounds = CGRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let frameCount = max(1, Int(ceil(duration * Double(targetFPS))))
        let maxSourceFrameIndex = max(0, Int(floor(duration * sourceFPS)))
        let maxReadableTime = max(0, duration - min(1 / sourceFPS, 0.001))
        var cachedImages: [Int: CGImage] = [:]

        for outputFrameIndex in 0..<frameCount {
            try Task.checkCancellation()
            try await waitUntilReady(input)

            guard writer.status == .writing else {
                throw writer.error ?? ExportError.exportFailed
            }

            let outputSeconds = min(Double(outputFrameIndex) / Double(targetFPS), maxReadableTime)
            let sourcePosition = outputSeconds * sourceFPS
            let lowerSourceIndex = min(max(0, Int(floor(sourcePosition))), maxSourceFrameIndex)
            let upperSourceIndex = min(lowerSourceIndex + 1, maxSourceFrameIndex)
            let blendAmount = sourcePosition - Double(lowerSourceIndex)

            let baseImage = try sourceImage(
                frameIndex: lowerSourceIndex,
                sourceFPS: sourceFPS,
                maxReadableTime: maxReadableTime,
                imageGenerator: imageGenerator,
                cache: &cachedImages
            )
            let baseCIImage = CIImage(cgImage: baseImage)
            var outputImage = scaledImage(baseCIImage, to: outputBounds)

            if preset.interpolationMode != .duplicate, blendAmount > 0.001, upperSourceIndex != lowerSourceIndex {
                let nextImage = try sourceImage(
                    frameIndex: upperSourceIndex,
                    sourceFPS: sourceFPS,
                    maxReadableTime: maxReadableTime,
                    imageGenerator: imageGenerator,
                    cache: &cachedImages
                )
                outputImage = interpolatedImage(
                    from: baseImage,
                    to: nextImage,
                    amount: blendAmount,
                    mode: preset.interpolationMode,
                    outputBounds: outputBounds,
                    opticalFlowInterpolator: opticalFlowInterpolator
                )
            }

            cachedImages = cachedImages.filter { abs($0.key - lowerSourceIndex) <= 2 }

            guard let pixelBuffer = makePixelBuffer(from: pixelBufferPool) else {
                throw ExportError.cannotCreatePixelBuffer
            }

            ciContext.render(outputImage, to: pixelBuffer, bounds: outputBounds, colorSpace: colorSpace)

            let presentationTime = CMTime(value: CMTimeValue(outputFrameIndex), timescale: CMTimeScale(targetFPS))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ExportError.exportFailed
            }
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        try await finishWriting(writer)
        return outputURL
    }

    private static func sourceDimensions(for track: AVAssetTrack) async throws -> (width: Int, height: Int) {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())
        return (max(2, width), max(2, height))
    }

    private static func sanitizedFrameRate(_ nominalFrameRate: Float) -> Double {
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            return 30
        }

        return Double(nominalFrameRate)
    }

    private static func sourceImage(
        frameIndex: Int,
        sourceFPS: Double,
        maxReadableTime: Double,
        imageGenerator: AVAssetImageGenerator,
        cache: inout [Int: CGImage]
    ) throws -> CGImage {
        if let cachedImage = cache[frameIndex] {
            return cachedImage
        }

        let seconds = min(Double(frameIndex) / sourceFPS, maxReadableTime)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let image = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        cache[frameIndex] = image
        return image
    }

    private static func scaledImage(_ image: CIImage, to outputBounds: CGRect) -> CIImage {
        let scaleX = outputBounds.width / max(1, image.extent.width)
        let scaleY = outputBounds.height / max(1, image.extent.height)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            return image
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: outputBounds)
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scaleY, forKey: kCIInputScaleKey)
        filter.setValue(scaleX / max(0.0001, scaleY), forKey: kCIInputAspectRatioKey)
        return filter.outputImage?.cropped(to: outputBounds) ?? image.cropped(to: outputBounds)
    }

    private static func interpolatedImage(
        from startImage: CGImage,
        to endImage: CGImage,
        amount: Double,
        mode: SmoothVideoInterpolationMode,
        outputBounds: CGRect,
        opticalFlowInterpolator: MetalOpticalFlowInterpolator?
    ) -> CIImage {
        let startCIImage = CIImage(cgImage: startImage)
        let endCIImage = CIImage(cgImage: endImage)

        switch mode {
        case .duplicate:
            return scaledImage(startCIImage, to: outputBounds)
        case .blend:
            let scaledStart = scaledImage(startCIImage, to: outputBounds)
            let scaledEnd = scaledImage(endCIImage, to: outputBounds)
            return blendedImage(from: scaledStart, to: scaledEnd, amount: amount)
        case .opticalFlow:
            guard let predictedImage = opticalFlowPredictedImage(
                from: startImage,
                to: endImage,
                amount: amount,
                interpolator: opticalFlowInterpolator
            ) else {
                let scaledStart = scaledImage(startCIImage, to: outputBounds)
                let scaledEnd = scaledImage(endCIImage, to: outputBounds)
                return blendedImage(from: scaledStart, to: scaledEnd, amount: amount)
            }

            let scaledPredicted = scaledImage(predictedImage, to: outputBounds)
            let scaledEnd = scaledImage(endCIImage, to: outputBounds)
            return blendedImage(from: scaledPredicted, to: scaledEnd, amount: amount * 0.25)
        }
    }

    private static func blendedImage(from startImage: CIImage, to endImage: CIImage, amount: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIDissolveTransition") else {
            return startImage
        }

        filter.setValue(startImage, forKey: kCIInputImageKey)
        filter.setValue(endImage, forKey: kCIInputTargetImageKey)
        filter.setValue(amount, forKey: kCIInputTimeKey)
        return filter.outputImage?.cropped(to: startImage.extent) ?? startImage
    }

    private static func opticalFlowPredictedImage(
        from startImage: CGImage,
        to endImage: CGImage,
        amount: Double,
        interpolator: MetalOpticalFlowInterpolator?
    ) -> CIImage? {
        guard let interpolator else { return nil }

        let request = VNGenerateOpticalFlowRequest(targetedCGImage: endImage, options: [:])
        request.computationAccuracy = .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half
        configureOpticalFlowComputeDevice(request)

        let handler = VNImageRequestHandler(cgImage: startImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let flowBuffer = request.results?.first?.pixelBuffer else {
            return nil
        }

        return interpolator.predictedImage(from: startImage, flowBuffer: flowBuffer, amount: amount)
    }

    private static func configureOpticalFlowComputeDevice(_ request: VNGenerateOpticalFlowRequest) {
        guard #available(macOS 14.0, *),
              let supportedDevices = try? request.supportedComputeStageDevices else {
            return
        }

        for stage in [VNComputeStage.main, VNComputeStage.postProcessing] {
            guard let gpu = supportedDevices[stage]?.first(where: { device in
                if case .gpu = device {
                    return true
                }
                return false
            }) else {
                continue
            }
            request.setComputeDevice(gpu, for: stage)
        }
    }

    private final class MetalOpticalFlowInterpolator {
        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let pipeline: MTLComputePipelineState
        private let textureLoader: MTKTextureLoader
        private let textureCache: CVMetalTextureCache
        private let colorSpace = CGColorSpaceCreateDeviceRGB()

        init(device: MTLDevice) throws {
            self.device = device
            guard let commandQueue = device.makeCommandQueue() else {
                throw MetalInterpolationError.cannotCreateCommandQueue
            }
            self.commandQueue = commandQueue

            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "opticalFlowInterpolate") else {
                throw MetalInterpolationError.missingFunction
            }
            self.pipeline = try device.makeComputePipelineState(function: function)
            self.textureLoader = MTKTextureLoader(device: device)

            var textureCache: CVMetalTextureCache?
            let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
            guard status == kCVReturnSuccess, let textureCache else {
                throw MetalInterpolationError.cannotCreateTextureCache
            }
            self.textureCache = textureCache
        }

        func predictedImage(from startImage: CGImage, flowBuffer: CVPixelBuffer, amount: Double) -> CIImage? {
            guard let sourceTexture = try? textureLoader.newTexture(
                cgImage: startImage,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
                ]
            ),
                  let flowTexture = flowTexture(from: flowBuffer),
                  let outputTexture = makeOutputTexture(width: sourceTexture.width, height: sourceTexture.height),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                return nil
            }

            var interpolationAmount = Float(amount)
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(sourceTexture, index: 0)
            encoder.setTexture(flowTexture, index: 1)
            encoder.setTexture(outputTexture, index: 2)
            encoder.setBytes(&interpolationAmount, length: MemoryLayout<Float>.size, index: 0)

            let threadWidth = max(1, pipeline.threadExecutionWidth)
            let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
            let threadsPerThreadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
            let threadgroups = MTLSize(
                width: (sourceTexture.width + threadWidth - 1) / threadWidth,
                height: (sourceTexture.height + threadHeight - 1) / threadHeight,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            guard commandBuffer.status == .completed,
                  let image = CIImage(mtlTexture: outputTexture, options: [.colorSpace: colorSpace]) else {
                return nil
            }

            let extent = CGRect(x: 0, y: 0, width: outputTexture.width, height: outputTexture.height)
            return image
                .transformed(by: CGAffineTransform(translationX: 0, y: extent.height).scaledBy(x: 1, y: -1))
                .cropped(to: extent)
        }

        private func flowTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var texture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .rg16Float,
                width,
                height,
                0,
                &texture
            )
            guard status == kCVReturnSuccess, let texture else { return nil }
            return CVMetalTextureGetTexture(texture)
        }

        private func makeOutputTexture(width: Int, height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }

        private enum MetalInterpolationError: Error {
            case cannotCreateCommandQueue
            case missingFunction
            case cannotCreateTextureCache
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void opticalFlowInterpolate(
            texture2d<float, access::sample> source [[texture(0)]],
            texture2d<half, access::sample> flow [[texture(1)]],
            texture2d<float, access::write> output [[texture(2)]],
            constant float &amount [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
                return;
            }

            constexpr sampler linearSampler(coord::pixel, address::clamp_to_edge, filter::linear);
            float2 destination = float2(gid) + float2(0.5);
            float2 sourceSize = float2(source.get_width(), source.get_height());
            float2 flowSize = float2(flow.get_width(), flow.get_height());
            float2 flowCoordinate = destination / sourceSize * flowSize;
            float2 motion = float2(flow.sample(linearSampler, flowCoordinate).rg);
            float2 sourceCoordinate = destination - motion * amount;
            float4 color = source.sample(linearSampler, sourceCoordinate);
            output.write(color, gid);
        }
        """
    }

    private static func makePixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard result == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private static func outputSettings(outputSize: SmoothVideoExportDimensions, targetFPS: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: averageBitRate(outputSize: outputSize, targetFPS: targetFPS),
                AVVideoExpectedSourceFrameRateKey: targetFPS
            ]
        ]
    }

    private static func averageBitRate(outputSize: SmoothVideoExportDimensions, targetFPS: Int) -> Int {
        let pixelsPerSecond = Double(outputSize.width * outputSize.height * targetFPS)
        return Int(min(120_000_000, max(8_000_000, pixelsPerSecond * 0.08)))
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private static func finishWriting(_ writer: AVAssetWriter) async throws {
        await writer.finishWriting()
        switch writer.status {
        case .completed:
            return
        case .failed, .cancelled:
            throw writer.error ?? ExportError.exportFailed
        default:
            throw ExportError.exportFailed
        }
    }

    private static func generatedOutputURL(
        assetID: UUID,
        sourceDisplayName: String,
        preset: SmoothVideoExportPreset,
        outputSize: SmoothVideoExportDimensions
    ) throws -> URL {
        let safeName = sourceDisplayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let directory = try generatedDirectory()
        return directory
            .appendingPathComponent(
                "\(safeName)-\(assetID.uuidString.prefix(8))-\(preset.normalizedTargetFPS)fps-\(outputSize.width)x\(outputSize.height)"
            )
            .appendingPathExtension("mov")
    }

    static func generatedDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL
            .appendingPathComponent("MacWallpaperEngine", isDirectory: true)
            .appendingPathComponent("GeneratedSmoothCopies", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    enum ExportError: LocalizedError {
        case missingVideoTrack
        case unreadableDuration
        case cannotAddVideoInput
        case missingMetalDevice
        case missingPixelBufferPool
        case cannotCreatePixelBuffer
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                "The source video does not contain a video track."
            case .unreadableDuration:
                "The source video duration could not be read."
            case .cannotAddVideoInput:
                "Could not create a generated-copy video writer."
            case .missingMetalDevice:
                "This Mac does not expose a Metal GPU for generated-copy rendering."
            case .missingPixelBufferPool:
                "Could not allocate generated-copy frame buffers."
            case .cannotCreatePixelBuffer:
                "Could not create a generated-copy frame."
            case .exportFailed:
                "The generated smooth copy did not complete."
            }
        }
    }
}
