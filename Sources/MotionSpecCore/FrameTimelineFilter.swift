import Foundation

public struct FrameTimelineFilter: Equatable, Sendable {
    public var minimumSpacing: TimeInterval
    public var startTimestamp: TimeInterval?

    private let timestampTolerance: TimeInterval = 0.000_5

    public init(
        minimumSpacing: TimeInterval = 0,
        startTimestamp: TimeInterval? = nil
    ) {
        self.minimumSpacing = max(0, minimumSpacing)
        self.startTimestamp = startTimestamp.map { max(0, $0) }
    }

    public func filter(_ frames: [MotionFrameCandidate]) -> [MotionFrameCandidate] {
        let chronologicalFrames = frames.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id < $1.id
            }

            return $0.timestamp < $1.timestamp
        }
        let candidateFrames = chronologicalFrames.filter { frame in
            guard let startTimestamp else {
                return true
            }

            return frame.timestamp + timestampTolerance >= startTimestamp
        }

        guard minimumSpacing > 0 else {
            return candidateFrames
        }

        var visibleFrames: [MotionFrameCandidate] = []
        var lastVisibleTimestamp: TimeInterval?

        for frame in candidateFrames {
            guard let lastTimestamp = lastVisibleTimestamp else {
                visibleFrames.append(frame)
                lastVisibleTimestamp = frame.timestamp
                continue
            }

            if frame.timestamp + timestampTolerance >= lastTimestamp + minimumSpacing {
                visibleFrames.append(frame)
                lastVisibleTimestamp = frame.timestamp
            }
        }

        return visibleFrames
    }
}
