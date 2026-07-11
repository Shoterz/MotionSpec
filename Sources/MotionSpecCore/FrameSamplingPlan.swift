import Foundation

public struct FrameSamplingPlan: Equatable, Sendable {
    public var frameRate: Double
    public var maximumFrameCount: Int

    public init(frameRate: Double, maximumFrameCount: Int = 240) {
        self.frameRate = frameRate
        self.maximumFrameCount = maximumFrameCount
    }

    public func timestamps(forDuration duration: TimeInterval) -> [TimeInterval] {
        guard duration > 0, frameRate > 0, maximumFrameCount > 0 else {
            return []
        }

        let uncappedCount = Int((duration * frameRate).rounded(.down)) + 1
        let frameCount = min(max(uncappedCount, 2), maximumFrameCount)

        guard frameCount > 1 else {
            return [0]
        }

        return (0..<frameCount).map { index in
            let progress = Double(index) / Double(frameCount - 1)
            return duration * progress
        }
    }
}
