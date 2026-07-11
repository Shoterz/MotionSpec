import Foundation

public struct FrameSelectionEngine: Sendable {
    private let staticClipThreshold: Double

    public init(staticClipThreshold: Double = 0.05) {
        self.staticClipThreshold = staticClipThreshold
    }

    public func selectFrames(
        from frames: [MotionFrameCandidate],
        count: Int,
        mode: FrameSelectionMode
    ) -> [MotionFrameCandidate] {
        let chronologicalFrames = frames.sorted { $0.timestamp < $1.timestamp }

        guard count > 0 else {
            return []
        }

        guard chronologicalFrames.count > count else {
            return chronologicalFrames
        }

        switch mode {
        case .evenIntervals:
            return selectEvenIntervals(from: chronologicalFrames, count: count)
        case .smartKeyframes:
            return selectSmartKeyframes(from: chronologicalFrames, count: count)
        case .manual:
            return selectEvenIntervals(from: chronologicalFrames, count: count)
        }
    }

    public func selectManualFrames(
        from frames: [MotionFrameCandidate],
        selectedIDs: [String]
    ) -> [MotionFrameCandidate] {
        let selectedIDSet = Set(selectedIDs)

        return frames
            .sorted { $0.timestamp < $1.timestamp }
            .filter { selectedIDSet.contains($0.id) }
    }

    private func selectEvenIntervals(
        from frames: [MotionFrameCandidate],
        count: Int
    ) -> [MotionFrameCandidate] {
        guard count > 1 else {
            return Array(frames.prefix(count))
        }

        let lastIndex = frames.count - 1
        var selectedIndexes: [Int] = []

        for slot in 0..<count {
            let position = Double(slot) * Double(lastIndex) / Double(count - 1)
            let index = Int(position.rounded())

            if !selectedIndexes.contains(index) {
                selectedIndexes.append(index)
            }
        }

        return selectedIndexes.map { frames[$0] }
    }

    private func selectSmartKeyframes(
        from frames: [MotionFrameCandidate],
        count: Int
    ) -> [MotionFrameCandidate] {
        let largestChange = frames.map(\.changeScore).max() ?? 0

        guard largestChange > staticClipThreshold else {
            return selectEvenIntervals(from: frames, count: count)
        }

        let first = frames[0]
        let last = frames[frames.count - 1]
        let interiorCount = max(count - 2, 0)
        let interiorFrames = frames
            .dropFirst()
            .dropLast()
            .sorted {
                if $0.changeScore == $1.changeScore {
                    return $0.timestamp < $1.timestamp
                }

                return $0.changeScore > $1.changeScore
            }
            .prefix(interiorCount)

        return ([first] + interiorFrames + [last])
            .sorted { $0.timestamp < $1.timestamp }
    }
}
