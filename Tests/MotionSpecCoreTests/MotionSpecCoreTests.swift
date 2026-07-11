import Foundation
import Testing
@testable import MotionSpecCore

@Suite
struct CaptureWorkflowTests {
    @Test("Workflow records region, window, and screen captures")
    func recordsEveryCaptureMode() throws {
        for mode in CaptureMode.allCases {
            var workflow = CaptureWorkflow()
            let target = target(for: mode)
            let startedAt = Date(timeIntervalSince1970: 42)
            let recordingURL = URL(filePath: "/tmp/motionspec-\(mode.rawValue).mov")
            let frames = sampleFrames(count: 4)

            workflow.beginCapture(mode)
            #expect(workflow.phase == .awaitingTarget(mode))

            try workflow.setTarget(target)
            #expect(workflow.phase == .readyToRecord(mode: mode, target: target))

            try workflow.startRecording(at: startedAt)
            #expect(workflow.phase == .recording(mode: mode, target: target, startedAt: startedAt))

            try workflow.finishRecording(recordingURL: recordingURL, duration: 2.0, frames: frames)
            #expect(workflow.phase == .review(
                CaptureReviewSession(
                    mode: mode,
                    target: target,
                    recordingURL: recordingURL,
                    duration: 2.0,
                    frames: frames
                )
            ))
        }
    }

    @Test("Workflow rejects a mismatched target for the selected mode")
    func rejectsMismatchedTarget() throws {
        var workflow = CaptureWorkflow()
        workflow.beginCapture(.region)

        #expect(throws: CaptureWorkflowError.targetModeMismatch) {
            try workflow.setTarget(.screen(DisplayCaptureTarget(displayID: 1, name: "Main Display")))
        }
    }

    @Test("Workflow reset returns to idle and clears ephemeral review state")
    func resetReturnsToIdle() throws {
        var workflow = CaptureWorkflow()
        workflow.beginCapture(.screen)
        try workflow.setTarget(.screen(DisplayCaptureTarget(displayID: 1, name: "Main Display")))
        try workflow.startRecording(at: Date(timeIntervalSince1970: 1))
        try workflow.finishRecording(
            recordingURL: URL(filePath: "/tmp/capture.mov"),
            duration: 1.4,
            frames: sampleFrames(count: 3)
        )

        workflow.reset()

        #expect(workflow.phase == .idle)
    }
}

@Suite
struct FrameSelectionEngineTests {
    @Test("Even intervals selects four chronological frames across the full clip")
    func evenIntervalsSelectsAcrossFullClip() {
        let frames = sampleFrames(count: 10)

        let selected = FrameSelectionEngine().selectFrames(
            from: frames,
            count: 4,
            mode: .evenIntervals
        )

        #expect(selected.map(\.id) == ["frame-0", "frame-3", "frame-6", "frame-9"])
    }

    @Test("Smart keyframes keeps endpoints and strongest visual changes")
    func smartKeyframesSelectsChangePeaks() {
        let frames = sampleFrames(changeScores: [0, 0.1, 0.95, 0.2, 0.1, 0.3, 0.82, 0.2, 0.4, 0.1])

        let selected = FrameSelectionEngine().selectFrames(
            from: frames,
            count: 4,
            mode: .smartKeyframes
        )

        #expect(selected.map(\.id) == ["frame-0", "frame-2", "frame-6", "frame-9"])
    }

    @Test("Smart keyframes falls back to even intervals for static clips")
    func smartKeyframesFallsBackForStaticClip() {
        let frames = sampleFrames(changeScores: Array(repeating: 0.01, count: 10))

        let selected = FrameSelectionEngine().selectFrames(
            from: frames,
            count: 4,
            mode: .smartKeyframes
        )

        #expect(selected.map(\.id) == ["frame-0", "frame-3", "frame-6", "frame-9"])
    }

    @Test("Selection returns all frames for very short clips")
    func returnsAllFramesForShortClip() {
        let frames = sampleFrames(count: 3)

        let selected = FrameSelectionEngine().selectFrames(
            from: frames,
            count: 4,
            mode: .smartKeyframes
        )

        #expect(selected.map(\.id) == ["frame-0", "frame-1", "frame-2"])
    }

    @Test("Manual selection returns requested frames in animation order")
    func manualSelectionReturnsRequestedFramesChronologically() {
        let frames = sampleFrames(count: 8)

        let selected = FrameSelectionEngine().selectManualFrames(
            from: frames,
            selectedIDs: ["frame-7", "frame-2", "missing"]
        )

        #expect(selected.map(\.id) == ["frame-2", "frame-7"])
    }
}

@Suite
struct MotionPromptBuilderTests {
    @Test("Builder prompt describes motion for implementation use")
    func buildsImplementationFocusedPrompt() {
        let frames = sampleFrames(count: 4)
        let review = CaptureReviewSession(
            mode: .region,
            target: .region(CaptureRegion(x: 10, y: 20, width: 320, height: 180)),
            recordingURL: URL(filePath: "/tmp/capture.mov"),
            duration: 2.0,
            frames: frames
        )

        let prompt = MotionPromptBuilder().buildPrompt(
            for: review,
            selectedFrames: frames,
            userNote: "Triggered by pressing the Save button."
        )

        #expect(prompt.contains("UI animation or transition"))
        #expect(prompt.contains("Frame 1 at 0.00s"))
        #expect(prompt.contains("Frame 4 at 0.30s"))
        #expect(prompt.contains("timing"))
        #expect(prompt.contains("easing"))
        #expect(prompt.contains("Triggered by pressing the Save button."))
    }
}

@Suite
struct CaptureReviewControllerTests {
    @Test("Loading a review selects smart keyframes by default")
    func loadSelectsSmartKeyframesByDefault() {
        var controller = CaptureReviewController()
        let review = sampleReview(changeScores: [0, 0.1, 0.95, 0.2, 0.1, 0.3, 0.82, 0.2, 0.4, 0.1])

        controller.load(review)

        #expect(controller.selectionMode == .smartKeyframes)
        #expect(controller.selectedFrames.map(\.id) == ["frame-0", "frame-2", "frame-6", "frame-9"])
    }

    @Test("Changing selection mode recalculates selected frames")
    func changingSelectionModeRecalculatesFrames() {
        var controller = CaptureReviewController()
        controller.load(sampleReview(changeScores: [0, 0.1, 0.95, 0.2, 0.1, 0.3, 0.82, 0.2, 0.4, 0.1]))

        controller.changeSelectionMode(.evenIntervals)

        #expect(controller.selectionMode == .evenIntervals)
        #expect(controller.selectedFrames.map(\.id) == ["frame-0", "frame-3", "frame-6", "frame-9"])
    }

    @Test("Manual frame IDs switch the controller into manual selection")
    func manualFrameIDsSwitchSelectionMode() {
        var controller = CaptureReviewController()
        controller.load(sampleReview(count: 8))

        controller.useManualFrameIDs(["frame-7", "frame-2"])

        #expect(controller.selectionMode == .manual)
        #expect(controller.selectedFrames.map(\.id) == ["frame-2", "frame-7"])
    }

    @Test("Clearing a review removes selected frames and returns to smart mode")
    func clearRemovesReviewState() {
        var controller = CaptureReviewController()
        controller.load(sampleReview(count: 8))
        controller.useManualFrameIDs(["frame-7", "frame-2"])

        controller.clear()

        #expect(controller.reviewSession == nil)
        #expect(controller.selectionMode == .smartKeyframes)
        #expect(controller.selectedFrames.isEmpty)
    }
}

@Suite
struct FrameTimelineFilterTests {
    @Test("Zero spacing shows every candidate frame in chronological order")
    func zeroSpacingShowsEveryFrame() {
        let frames = sampleFrames(timestamps: [0.10, 0, 0.03])

        let visibleFrames = FrameTimelineFilter(minimumSpacing: 0).filter(frames)

        #expect(visibleFrames.map(\.timestamp) == [0, 0.03, 0.10])
    }

    @Test("Minimum spacing hides near-duplicate timeline frames")
    func minimumSpacingSkipsIntermediateFrames() {
        let frames = sampleFrames(timestamps: [0, 0.03, 0.07, 0.10, 0.13, 0.20, 0.27, 0.30])

        let visibleFrames = FrameTimelineFilter(minimumSpacing: 0.10).filter(frames)

        #expect(visibleFrames.map(\.timestamp) == [0, 0.10, 0.20, 0.30])
    }
}

@Suite
struct FrameSamplingPlanTests {
    @Test("Frame sampling covers the whole clip at the requested frame rate")
    func samplingCoversWholeClip() {
        let timestamps = FrameSamplingPlan(frameRate: 30).timestamps(forDuration: 2.0)

        #expect(timestamps.count == 61)
        #expect(timestamps.first == 0)
        #expect(timestamps.last == 2.0)
    }

    @Test("Frame sampling caps long clips to avoid heavy extraction")
    func samplingCapsLongClips() {
        let timestamps = FrameSamplingPlan(frameRate: 30, maximumFrameCount: 120)
            .timestamps(forDuration: 20.0)

        #expect(timestamps.count == 120)
        #expect(timestamps.first == 0)
        #expect(timestamps.last == 20.0)
    }
}

@Suite
struct OneShotGateTests {
    @Test("One-shot gate accepts the first completion and rejects later completions")
    func acceptsOnlyFirstCompletion() {
        var gate = OneShotGate()

        #expect(gate.accept() == true)
        #expect(gate.accept() == false)
        #expect(gate.accept() == false)
    }
}

@Suite(.serialized)
struct SessionExporterTests {
    @Test("Exporter copies frames and prompt while workspace cleanup removes ephemeral files")
    func exportsAndCleansEphemeralWorkspace() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "motionspec-tests-\(UUID().uuidString)")
        let workspace = try TemporarySessionWorkspace(
            baseDirectory: temporaryRoot,
            sessionID: "session-a"
        )
        let sourceDirectory = workspace.sessionDirectory.appending(path: "source")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let sourceFrame = sourceDirectory.appending(path: "original.png")
        try Data("fake-png".utf8).write(to: sourceFrame)
        let frame = MotionFrameCandidate(
            id: "frame-0",
            timestamp: 0,
            imageURL: sourceFrame,
            changeScore: 0
        )
        let exportDirectory = temporaryRoot.appending(path: "export")

        let manifest = try SessionExporter().export(
            frames: [frame],
            prompt: "Describe this motion.",
            to: exportDirectory
        )

        #expect(manifest.frameURLs.map { $0.lastPathComponent } == ["motion-frame-01.png"])
        #expect(manifest.promptURL.lastPathComponent == "motion-prompt.txt")
        #expect(FileManager.default.fileExists(atPath: manifest.frameURLs[0].path()))
        #expect(FileManager.default.fileExists(atPath: manifest.promptURL.path()))

        try workspace.cleanup()

        #expect(!FileManager.default.fileExists(atPath: workspace.sessionDirectory.path()))
    }
}

@Suite
struct AIRequestBuilderTests {
    @Test("Gemini request body includes text and multiple inline PNG frames")
    func geminiRequestBodyIncludesPromptAndImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "motionspec-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let first = directory.appending(path: "first.png")
        let second = directory.appending(path: "second.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: first)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x02]).write(to: second)
        let frames = [
            MotionFrameCandidate(id: "first", timestamp: 0, imageURL: first, changeScore: 0),
            MotionFrameCandidate(id: "second", timestamp: 0.5, imageURL: second, changeScore: 0.5)
        ]

        let body = try GeminiRequestBuilder(model: "gemini-3.5-flash")
            .makeRequestBody(prompt: "Describe the motion.", frames: frames)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let input = try #require(object["input"] as? [[String: Any]])

        #expect(object["model"] as? String == "gemini-3.5-flash")
        #expect(input.count == 3)
        #expect(input[0]["text"] as? String == "Describe the motion.")
        #expect(input[1]["mime_type"] as? String == "image/png")
        #expect(input[2]["mime_type"] as? String == "image/png")
        #expect((input[1]["data"] as? String)?.isEmpty == false)
    }

    @Test("Codex CLI command attaches every selected frame")
    func codexCommandAttachesFrames() {
        let frames = sampleFrames(count: 2)

        let command = CodexCLICommandBuilder(executablePath: "/usr/local/bin/codex")
            .makeCommand(prompt: "Describe.", frames: frames)

        #expect(command.executablePath == "/usr/local/bin/codex")
        #expect(command.arguments == [
            "exec",
            "--skip-git-repo-check",
            "--image",
            "/tmp/frame-0.png",
            "--image",
            "/tmp/frame-1.png",
            "Describe."
        ])
    }

    @Test("Custom CLI command expands prompt and frame placeholders without using a shell")
    func customCommandExpandsPlaceholders() throws {
        let frames = sampleFrames(count: 2)
        let promptFile = URL(filePath: "/tmp/prompt.txt")

        let command = try CustomCLICommandBuilder().makeCommand(
            template: "/opt/homebrew/bin/gemini --prompt-file {{promptFile}} {{frames}}",
            promptFile: promptFile,
            frames: frames
        )

        #expect(command.executablePath == "/opt/homebrew/bin/gemini")
        #expect(command.arguments == [
            "--prompt-file",
            "/tmp/prompt.txt",
            "/tmp/frame-0.png",
            "/tmp/frame-1.png"
        ])
    }
}

private func target(for mode: CaptureMode) -> CaptureTarget {
    switch mode {
    case .region:
        return .region(CaptureRegion(x: 10, y: 20, width: 300, height: 200))
    case .window:
        return .window(WindowCaptureTarget(windowID: 42, ownerName: "Demo", title: "Inspector"))
    case .screen:
        return .screen(DisplayCaptureTarget(displayID: 1, name: "Main Display"))
    }
}

private func sampleFrames(count: Int) -> [MotionFrameCandidate] {
    sampleFrames(changeScores: (0..<count).map { Double($0) / 10.0 })
}

private func sampleFrames(timestamps: [TimeInterval]) -> [MotionFrameCandidate] {
    timestamps.enumerated().map { index, timestamp in
        MotionFrameCandidate(
            id: "frame-\(index)",
            timestamp: timestamp,
            imageURL: URL(filePath: "/tmp/frame-\(index).png"),
            changeScore: Double(index) / 10.0
        )
    }
}

private func sampleFrames(changeScores: [Double]) -> [MotionFrameCandidate] {
    changeScores.enumerated().map { index, score in
        MotionFrameCandidate(
            id: "frame-\(index)",
            timestamp: Double(index) / 10.0,
            imageURL: URL(filePath: "/tmp/frame-\(index).png"),
            changeScore: score
        )
    }
}

private func sampleReview(count: Int) -> CaptureReviewSession {
    sampleReview(changeScores: (0..<count).map { Double($0) / 10.0 })
}

private func sampleReview(changeScores: [Double]) -> CaptureReviewSession {
    CaptureReviewSession(
        mode: .screen,
        target: .screen(DisplayCaptureTarget(displayID: 1, name: "Main Display")),
        recordingURL: URL(filePath: "/tmp/capture.mov"),
        duration: 2.0,
        frames: sampleFrames(changeScores: changeScores)
    )
}
