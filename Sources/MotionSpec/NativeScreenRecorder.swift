import AVFoundation
import CoreMedia
import Foundation
import MotionSpecCore
@preconcurrency import ScreenCaptureKit

final class NativeScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "MotionSpec.ScreenCapture")
    private var activeStream: SCStream?
    private var outputURL: URL?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPresentationTime: CMTime?

    func startRecording(target: CaptureTarget, outputDirectory: URL) async throws {
        guard activeStream == nil else {
            throw NativeScreenRecorderError.alreadyRecording
        }

        let preparedTarget = try await prepareTarget(target)
        let outputURL = outputDirectory.appending(path: "capture.mov")
        if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try configureWriter(outputURL: outputURL, size: preparedTarget.outputSize)

        let configuration = SCStreamConfiguration()
        configuration.width = Int(max(preparedTarget.outputSize.width, 1))
        configuration.height = Int(max(preparedTarget.outputSize.height, 1))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.capturesAudio = false

        if let sourceRect = preparedTarget.sourceRect {
            configuration.sourceRect = sourceRect
        }

        let stream = SCStream(
            filter: preparedTarget.filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        activeStream = stream
        self.outputURL = outputURL
    }

    func stopRecording() async throws -> URL {
        guard let activeStream, let outputURL else {
            throw NativeScreenRecorderError.notRecording
        }

        try await activeStream.stopCapture()
        try await finishWriting()

        self.activeStream = nil
        self.outputURL = nil
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        firstPresentationTime = nil

        return outputURL
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let assetWriter,
              let assetWriterInput,
              let pixelBufferAdaptor else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstPresentationTime == nil {
            firstPresentationTime = presentationTime
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: presentationTime)
        }

        guard assetWriterInput.isReadyForMoreMediaData else {
            return
        }

        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureQueue.async { [weak self] in
            self?.assetWriter?.cancelWriting()
        }
    }

    private func prepareTarget(_ target: CaptureTarget) async throws -> PreparedScreenCaptureTarget {
        let content = try await SCShareableContent.current

        switch target {
        case let .screen(displayTarget):
            let display = content.displays.first { $0.displayID == displayTarget.displayID }
                ?? content.displays.first
            guard let display else {
                throw NativeScreenRecorderError.noDisplay
            }

            return PreparedScreenCaptureTarget(
                filter: SCContentFilter(display: display, excludingWindows: []),
                outputSize: CGSize(width: display.width, height: display.height),
                sourceRect: nil
            )

        case let .window(windowTarget):
            guard let window = content.windows.first(where: { $0.windowID == windowTarget.windowID }) else {
                throw NativeScreenRecorderError.noWindow
            }

            return PreparedScreenCaptureTarget(
                filter: SCContentFilter(desktopIndependentWindow: window),
                outputSize: window.frame.size,
                sourceRect: nil
            )

        case let .region(region):
            let mainDisplayID = CGMainDisplayID()
            let display = content.displays.first { $0.displayID == mainDisplayID }
                ?? content.displays.first
            guard let display else {
                throw NativeScreenRecorderError.noDisplay
            }

            let sourceRect = CGRect(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height
            )

            return PreparedScreenCaptureTarget(
                filter: SCContentFilter(display: display, excludingWindows: []),
                outputSize: sourceRect.size,
                sourceRect: sourceRect
            )
        }
    }

    private func configureWriter(outputURL: URL, size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(max(size.width, 1)),
            AVVideoHeightKey: Int(max(size.height, 1))
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw NativeScreenRecorderError.cannotAddWriterInput
        }

        writer.add(input)

        assetWriter = writer
        assetWriterInput = input
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(max(size.width, 1)),
                kCVPixelBufferHeightKey as String: Int(max(size.height, 1))
            ]
        )
    }

    private func finishWriting() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            captureQueue.async { [weak self] in
                guard let self, let assetWriter, let assetWriterInput else {
                    continuation.resume(throwing: NativeScreenRecorderError.notRecording)
                    return
                }

                assetWriterInput.markAsFinished()
                let writerBox = AssetWriterSendableBox(assetWriter)
                assetWriter.finishWriting {
                    if writerBox.writer.status == .failed {
                        continuation.resume(
                            throwing: writerBox.writer.error ?? NativeScreenRecorderError.writerFailed
                        )
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}

private struct PreparedScreenCaptureTarget {
    var filter: SCContentFilter
    var outputSize: CGSize
    var sourceRect: CGRect?
}

private final class AssetWriterSendableBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

enum NativeScreenRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noDisplay
    case noWindow
    case cannotAddWriterInput
    case writerFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already active"
        case .notRecording:
            return "No recording is active"
        case .noDisplay:
            return "No display is available for capture"
        case .noWindow:
            return "The selected window is no longer available"
        case .cannotAddWriterInput:
            return "Could not prepare the video writer"
        case .writerFailed:
            return "The recording writer failed"
        }
    }
}
