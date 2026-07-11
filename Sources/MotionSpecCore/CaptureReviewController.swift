import Foundation

public struct CaptureReviewController: Sendable {
    public private(set) var reviewSession: CaptureReviewSession?
    public private(set) var selectionMode: FrameSelectionMode
    public private(set) var selectedFrames: [MotionFrameCandidate]

    private let defaultFrameCount: Int
    private let frameSelectionEngine: FrameSelectionEngine

    public init(
        defaultFrameCount: Int = 4,
        frameSelectionEngine: FrameSelectionEngine = FrameSelectionEngine()
    ) {
        self.defaultFrameCount = defaultFrameCount
        self.frameSelectionEngine = frameSelectionEngine
        selectionMode = .smartKeyframes
        selectedFrames = []
    }

    public mutating func load(_ reviewSession: CaptureReviewSession) {
        self.reviewSession = reviewSession
        selectionMode = .smartKeyframes
        selectedFrames = frameSelectionEngine.selectFrames(
            from: reviewSession.frames,
            count: defaultFrameCount,
            mode: selectionMode
        )
    }

    public mutating func changeSelectionMode(_ mode: FrameSelectionMode) {
        guard let reviewSession else {
            selectionMode = mode
            selectedFrames = []
            return
        }

        selectionMode = mode
        selectedFrames = frameSelectionEngine.selectFrames(
            from: reviewSession.frames,
            count: defaultFrameCount,
            mode: mode
        )
    }

    public mutating func useManualFrameIDs(_ frameIDs: [String]) {
        guard let reviewSession else {
            selectedFrames = []
            selectionMode = .manual
            return
        }

        selectionMode = .manual
        selectedFrames = frameSelectionEngine.selectManualFrames(
            from: reviewSession.frames,
            selectedIDs: frameIDs
        )
    }

    public mutating func clear() {
        reviewSession = nil
        selectionMode = .smartKeyframes
        selectedFrames = []
    }

    public func buildPrompt(userNote: String? = nil) -> String {
        guard let reviewSession else {
            return ""
        }

        return MotionPromptBuilder().buildPrompt(
            for: reviewSession,
            selectedFrames: selectedFrames,
            userNote: userNote
        )
    }
}
