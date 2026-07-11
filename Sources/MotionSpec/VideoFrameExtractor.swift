import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import MotionSpecCore

protocol VideoFrameExtracting: Sendable {
    func extractFrames(from videoURL: URL, into directory: URL) async throws -> [MotionFrameCandidate]
}

struct AVAssetVideoFrameExtractor: VideoFrameExtracting {
    private let samplingPlan: FrameSamplingPlan

    init(samplingPlan: FrameSamplingPlan = FrameSamplingPlan(frameRate: 30, maximumFrameCount: 240)) {
        self.samplingPlan = samplingPlan
    }

    func extractFrames(from videoURL: URL, into directory: URL) async throws -> [MotionFrameCandidate] {
        try await Task.detached {
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = max(CMTimeGetSeconds(duration), 0)
            let timestamps = samplingPlan.timestamps(forDuration: durationSeconds)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            var frames: [MotionFrameCandidate] = []
            var previousFingerprint: [Double]?

            for (index, timestamp) in timestamps.enumerated() {
                let time = CMTime(seconds: timestamp, preferredTimescale: 600)
                let image = try generator.copyCGImage(at: time, actualTime: nil)
                let imageURL = directory.appending(path: "candidate-\(String(format: "%04d", index + 1)).png")
                try writePNG(image: image, to: imageURL)

                let fingerprint = fingerprint(for: image)
                let changeScore = previousFingerprint.map {
                    differenceScore(previous: $0, current: fingerprint)
                } ?? 0
                previousFingerprint = fingerprint

                frames.append(
                    MotionFrameCandidate(
                        id: "frame-\(index)",
                        timestamp: timestamp,
                        imageURL: imageURL,
                        changeScore: changeScore
                    )
                )
            }

            return frames
        }.value
    }
}

private func writePNG(image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw VideoFrameExtractorError.cannotEncodePNG
    }

    try data.write(to: url, options: .atomic)
}

private func fingerprint(for image: CGImage) -> [Double] {
    let width = 8
    let height = 8
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return stride(from: 0, to: pixels.count, by: bytesPerPixel).map { index in
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        return (red + green + blue) / (3.0 * 255.0)
    }
}

private func differenceScore(previous: [Double], current: [Double]) -> Double {
    guard previous.count == current.count, !previous.isEmpty else {
        return 0
    }

    let total = zip(previous, current)
        .map { abs($0 - $1) }
        .reduce(0, +)

    return total / Double(previous.count)
}

private enum VideoFrameExtractorError: LocalizedError {
    case cannotEncodePNG

    var errorDescription: String? {
        switch self {
        case .cannotEncodePNG:
            return "Could not encode a frame as PNG"
        }
    }
}
