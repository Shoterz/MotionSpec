import Foundation

public enum CaptureWorkflowError: Error, Equatable, Sendable {
    case invalidTransition
    case targetModeMismatch
}

public enum CapturePhase: Equatable, Sendable {
    case idle
    case awaitingTarget(CaptureMode)
    case readyToRecord(mode: CaptureMode, target: CaptureTarget)
    case recording(mode: CaptureMode, target: CaptureTarget, startedAt: Date)
    case review(CaptureReviewSession)
    case failed(String)
}

public struct CaptureWorkflow: Equatable, Sendable {
    public private(set) var phase: CapturePhase

    public init(phase: CapturePhase = .idle) {
        self.phase = phase
    }

    public mutating func beginCapture(_ mode: CaptureMode) {
        phase = .awaitingTarget(mode)
    }

    public mutating func setTarget(_ target: CaptureTarget) throws(CaptureWorkflowError) {
        guard case let .awaitingTarget(mode) = phase else {
            throw .invalidTransition
        }

        guard target.mode == mode else {
            throw .targetModeMismatch
        }

        phase = .readyToRecord(mode: mode, target: target)
    }

    public mutating func startRecording(at startedAt: Date) throws(CaptureWorkflowError) {
        guard case let .readyToRecord(mode, target) = phase else {
            throw .invalidTransition
        }

        phase = .recording(mode: mode, target: target, startedAt: startedAt)
    }

    public mutating func finishRecording(
        recordingURL: URL,
        duration: TimeInterval,
        frames: [MotionFrameCandidate]
    ) throws(CaptureWorkflowError) {
        guard case let .recording(mode, target, _) = phase else {
            throw .invalidTransition
        }

        phase = .review(
            CaptureReviewSession(
                mode: mode,
                target: target,
                recordingURL: recordingURL,
                duration: duration,
                frames: frames
            )
        )
    }

    public mutating func fail(with message: String) {
        phase = .failed(message)
    }

    public mutating func reset() {
        phase = .idle
    }
}
