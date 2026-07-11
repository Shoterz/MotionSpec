import Foundation
import Testing
@testable import MotionSpec
@testable import MotionSpecCore

@MainActor
@Suite
struct ReviewTimelineModelTests {
    @Test("Start frame trims visible frames and output selection")
    func startFrameTrimsVisibleFramesAndOutputSelection() {
        let model = MotionSpecAppModel()
        let review = sampleReview(timestamps: [0, 0.03, 0.10, 0.20, 0.30])
        model.reviewController.load(review)
        model.visibleFrameSpacing = 0.10

        let startFrame = review.frames[2]
        model.setTimelineStart(startFrame)

        #expect(model.visibleFrames.map(\.id) == ["frame-2", "frame-3", "frame-4"])
        #expect(model.selectedFrames.map(\.id) == ["frame-2", "frame-3", "frame-4"])
    }

    @Test("Carousel navigation moves through visible frames and clamps at bounds")
    func carouselNavigationMovesThroughVisibleFrames() throws {
        let model = MotionSpecAppModel()
        let review = sampleReview(timestamps: [0, 0.03, 0.10, 0.20, 0.30])
        model.reviewController.load(review)
        model.visibleFrameSpacing = 0.10
        model.setTimelineStart(review.frames[2])
        model.focusFrame(review.frames[2])

        model.showNextCarouselFrame()
        #expect(model.focusedFrame?.id == "frame-3")

        model.showNextCarouselFrame()
        #expect(model.focusedFrame?.id == "frame-4")

        model.showNextCarouselFrame()
        #expect(model.focusedFrame?.id == "frame-4")

        model.showPreviousCarouselFrame()
        #expect(model.focusedFrame?.id == "frame-3")
    }

    @Test("Focused frame selection toggles on and off")
    func focusedFrameSelectionTogglesOnAndOff() {
        let model = MotionSpecAppModel()
        let review = sampleReview(timestamps: [0, 0.10, 0.20, 0.30, 0.40])
        model.reviewController.load(review)
        model.focusFrame(review.frames[1])

        model.toggleFocusedFrameSelection()

        #expect(model.frameSelectionMode == .manual)
        #expect(model.selectedFrames.map(\.id) == ["frame-0", "frame-1", "frame-2", "frame-3", "frame-4"])

        model.toggleFocusedFrameSelection()

        #expect(model.selectedFrames.map(\.id) == ["frame-0", "frame-2", "frame-3", "frame-4"])
    }
}

private func sampleReview(timestamps: [TimeInterval]) -> CaptureReviewSession {
    let frames = timestamps.enumerated().map { index, timestamp in
        MotionFrameCandidate(
            id: "frame-\(index)",
            timestamp: timestamp,
            imageURL: URL(filePath: "/tmp/frame-\(index).png"),
            changeScore: Double(index) / 10.0
        )
    }

    return CaptureReviewSession(
        mode: .screen,
        target: .screen(DisplayCaptureTarget(displayID: 1, name: "Main Display")),
        recordingURL: URL(filePath: "/tmp/capture.mov"),
        duration: timestamps.last ?? 0,
        frames: frames
    )
}
