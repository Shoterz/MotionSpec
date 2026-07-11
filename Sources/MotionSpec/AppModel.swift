import AppKit
import Foundation
import MotionSpecCore
import Observation

@MainActor
@Observable
final class MotionSpecAppModel {
    var captureMode: CaptureMode = .region
    var frameSelectionMode: FrameSelectionMode = .smartKeyframes
    var aiProvider: AIProvider = .geminiAPI
    var selectedWindow: WindowCaptureTarget?
    var availableWindows: [WindowCaptureTarget] = []
    var workflow = CaptureWorkflow()
    var reviewController = CaptureReviewController()
    var userNote = ""
    var geminiAPIKey = ""
    var customCLICommand = "/opt/homebrew/bin/gemini --prompt-file {{promptFile}} {{frames}}"
    var statusMessage = "Ready"
    var aiDescription = ""
    var isRecording = false
    var isPreparingCapture = false
    var visibleFrameSpacing: TimeInterval = 0
    var thumbnailColumns = ReviewGridPreferences.defaultColumns
    var reviewDisplayMode: ReviewDisplayMode = .grid
    var timelineStartFrameID: String?
    var focusedFrameID: String?
    var manualFrameIDs: [String] = []

    @ObservationIgnored private let targetResolver = NativeCaptureTargetResolver()
    @ObservationIgnored private let regionSelector = RegionSelectionController()
    @ObservationIgnored private let recorder = NativeScreenRecorder()
    @ObservationIgnored private let frameExtractor = AVAssetVideoFrameExtractor()
    @ObservationIgnored private let clipboardWriter = ClipboardWriter()
    @ObservationIgnored private let geminiClient = GeminiMotionDescriptionClient()
    @ObservationIgnored private let cliRunner = CLIProviderRunner()
    @ObservationIgnored private let keychainStore = KeychainStore(service: "MotionSpec")
    @ObservationIgnored private let frameSelectionEngine = FrameSelectionEngine()
    @ObservationIgnored private let defaultFrameCount = 4
    @ObservationIgnored private var activeWorkspace: TemporarySessionWorkspace?
    @ObservationIgnored private var recordingStartedAt: Date?

    var selectedFrames: [MotionFrameCandidate] {
        switch frameSelectionMode {
        case .manual:
            return frameSelectionEngine.selectManualFrames(
                from: visibleFrames,
                selectedIDs: manualFrameIDs
            )
        case .smartKeyframes, .evenIntervals:
            return frameSelectionEngine.selectFrames(
                from: visibleFrames,
                count: defaultFrameCount,
                mode: frameSelectionMode
            )
        }
    }

    var currentReview: CaptureReviewSession? {
        reviewController.reviewSession
    }

    var visibleFrames: [MotionFrameCandidate] {
        guard let currentReview else {
            return []
        }
        let startTimestamp = timelineStartFrame?.timestamp

        return FrameTimelineFilter(
            minimumSpacing: visibleFrameSpacing,
            startTimestamp: startTimestamp
        )
            .filter(currentReview.frames)
    }

    var timelineStartFrame: MotionFrameCandidate? {
        guard let timelineStartFrameID, let currentReview else {
            return nil
        }

        return currentReview.frames.first { $0.id == timelineStartFrameID }
    }

    var focusedFrame: MotionFrameCandidate? {
        let frames = visibleFrames

        if let focusedFrameID,
           let frame = frames.first(where: { $0.id == focusedFrameID }) {
            return frame
        }

        return frames.first
    }

    var canStopRecording: Bool {
        isRecording
    }

    var canStartCapture: Bool {
        !isRecording && !isPreparingCapture
    }

    var canUseOutputs: Bool {
        currentReview != nil && !selectedFrames.isEmpty
    }

    var canClearSession: Bool {
        currentReview != nil
            || !aiDescription.isEmpty
            || !userNote.isEmpty
            || activeWorkspace != nil
            || workflow.phase != .idle
    }

    init() {
        geminiAPIKey = (try? keychainStore.loadPassword(account: "gemini-api-key")) ?? ""
    }

    func refreshWindows() {
        Task {
            do {
                availableWindows = try await targetResolver.availableWindows()
                if selectedWindow == nil {
                    selectedWindow = availableWindows.first
                }
                statusMessage = "Windows refreshed"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func startCapture(_ mode: CaptureMode? = nil) {
        Task {
            await startCaptureFlow(mode ?? captureMode)
        }
    }

    func stopCapture() {
        Task {
            await stopCaptureFlow()
        }
    }

    func changeFrameSelectionMode(_ mode: FrameSelectionMode) {
        let currentSelectedIDs = selectedFrames.map(\.id)
        frameSelectionMode = mode
        manualFrameIDs = mode == .manual ? currentSelectedIDs : []
        reviewController.changeSelectionMode(mode)
    }

    func toggleManualFrame(_ frame: MotionFrameCandidate) {
        if frameSelectionMode != .manual {
            manualFrameIDs = selectedFrames.map(\.id)
            frameSelectionMode = .manual
        }

        if let index = manualFrameIDs.firstIndex(of: frame.id) {
            manualFrameIDs.remove(at: index)
        } else {
            manualFrameIDs.append(frame.id)
        }

        reviewController.useManualFrameIDs(manualFrameIDs)
    }

    func setThumbnailColumns(_ columns: Int) {
        thumbnailColumns = ReviewGridPreferences.clampedColumns(columns)
    }

    func setTimelineStart(_ frame: MotionFrameCandidate) {
        timelineStartFrameID = frame.id
        focusedFrameID = frame.id
        keepManualSelectionInsideVisibleTimeline()
    }

    func resetTimelineStart() {
        timelineStartFrameID = nil
        focusedFrameID = visibleFrames.first?.id
        keepManualSelectionInsideVisibleTimeline()
    }

    func focusFrame(_ frame: MotionFrameCandidate) {
        focusedFrameID = frame.id
    }

    func showPreviousCarouselFrame() {
        moveCarouselFocus(by: -1)
    }

    func showNextCarouselFrame() {
        moveCarouselFocus(by: 1)
    }

    func toggleFocusedFrameSelection() {
        guard let focusedFrame else {
            return
        }

        toggleManualFrame(focusedFrame)
    }

    func clearSession() {
        guard !isRecording && !isPreparingCapture else {
            statusMessage = isRecording ? "Stop recording before clearing" : "Finish capture selection before clearing"
            return
        }

        let cleanupError: Error?
        do {
            try activeWorkspace?.cleanup()
            cleanupError = nil
        } catch {
            cleanupError = error
        }

        activeWorkspace = nil
        recordingStartedAt = nil
        workflow.reset()
        reviewController.clear()
        frameSelectionMode = reviewController.selectionMode
        manualFrameIDs = []
        timelineStartFrameID = nil
        focusedFrameID = nil
        userNote = ""
        aiDescription = ""

        if let cleanupError {
            statusMessage = "Cleared, but temp cleanup failed: \(cleanupError.localizedDescription)"
        } else {
            statusMessage = "Cleared. Ready for a new recording"
        }
    }

    func copyImagesAndPrompt() {
        guard let review = currentReview else {
            statusMessage = "No capture to copy"
            return
        }

        let prompt = MotionPromptBuilder().buildPrompt(
            for: review,
            selectedFrames: selectedFrames,
            userNote: userNote
        )
        clipboardWriter.copy(frames: selectedFrames, prompt: prompt)
        statusMessage = "Copied frames and prompt"
    }

    func exportFolder() {
        guard let review = currentReview else {
            statusMessage = "No capture to export"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        do {
            let prompt = MotionPromptBuilder().buildPrompt(
                for: review,
                selectedFrames: selectedFrames,
                userNote: userNote
            )
            _ = try SessionExporter().export(
                frames: selectedFrames,
                prompt: prompt,
                to: directory
            )
            statusMessage = "Exported frames and prompt"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func describeWithAI() {
        Task {
            await describeSelectedFrames()
        }
    }

    func saveGeminiAPIKey() {
        do {
            try keychainStore.savePassword(geminiAPIKey, account: "gemini-api-key")
            statusMessage = "Gemini key saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func startCaptureFlow(_ mode: CaptureMode) async {
        guard canStartCapture else {
            statusMessage = isRecording ? "Already recording" : "Capture already starting"
            return
        }

        isPreparingCapture = true

        do {
            workflow.beginCapture(mode)
            statusMessage = mode == .region ? "Select a region" : "Preparing capture"
            let target = try await resolveTarget(for: mode)
            try workflow.setTarget(target)
            try workflow.startRecording(at: Date())
            recordingStartedAt = Date()

            let workspace = try TemporarySessionWorkspace(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appending(path: "motionspec", directoryHint: .isDirectory)
            )
            let previousWorkspace = activeWorkspace

            try await recorder.startRecording(
                target: target,
                outputDirectory: workspace.sessionDirectory
            )

            try? previousWorkspace?.cleanup()
            activeWorkspace = workspace
            reviewController.clear()
            frameSelectionMode = reviewController.selectionMode
            aiDescription = ""
            isRecording = true
            isPreparingCapture = false
            statusMessage = "Recording \(mode.rawValue)"
        } catch {
            isPreparingCapture = false
            workflow.fail(with: error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func stopCaptureFlow() async {
        guard isRecording else {
            statusMessage = "Not recording"
            return
        }

        do {
            let recordingURL = try await recorder.stopRecording()
            let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            isRecording = false
            statusMessage = "Extracting frames"

            let workspace = try requireActiveWorkspace()
            let frames = try await frameExtractor.extractFrames(
                from: recordingURL,
                into: workspace.sessionDirectory
            )

            try workflow.finishRecording(
                recordingURL: recordingURL,
                duration: duration,
                frames: frames
            )

            if case let .review(review) = workflow.phase {
                reviewController.load(review)
                frameSelectionMode = reviewController.selectionMode
                manualFrameIDs = []
                timelineStartFrameID = nil
                focusedFrameID = review.frames.first?.id
            }

            statusMessage = "Ready to copy or describe"
        } catch {
            isRecording = false
            workflow.fail(with: error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func resolveTarget(for mode: CaptureMode) async throws -> CaptureTarget {
        switch mode {
        case .region:
            let region = try await regionSelector.selectRegion()
            return .region(region)
        case .window:
            if let selectedWindow {
                return .window(selectedWindow)
            }

            let windows = try await targetResolver.availableWindows()
            availableWindows = windows

            guard let firstWindow = windows.first else {
                throw MotionSpecAppError.noWindowAvailable
            }

            selectedWindow = firstWindow
            return .window(firstWindow)
        case .screen:
            return try await targetResolver.mainDisplayTarget()
        }
    }

    private func describeSelectedFrames() async {
        guard let review = currentReview else {
            statusMessage = "No capture to describe"
            return
        }

        let prompt = MotionPromptBuilder().buildPrompt(
            for: review,
            selectedFrames: selectedFrames,
            userNote: userNote
        )

        do {
            statusMessage = "Describing motion"
            switch aiProvider {
            case .geminiAPI:
                guard !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MotionSpecAppError.missingGeminiAPIKey
                }
                aiDescription = try await geminiClient.describe(
                    prompt: prompt,
                    frames: selectedFrames,
                    apiKey: geminiAPIKey
                )
            case .codexCLI:
                let command = CodexCLICommandBuilder().makeCommand(
                    prompt: prompt,
                    frames: selectedFrames
                )
                aiDescription = try await cliRunner.run(command)
            case .customCLI:
                let workspace = try requireActiveWorkspace()
                let promptFile = workspace.sessionDirectory.appending(path: "motion-prompt.txt")
                try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
                let command = try CustomCLICommandBuilder().makeCommand(
                    template: customCLICommand,
                    promptFile: promptFile,
                    frames: selectedFrames
                )
                aiDescription = try await cliRunner.run(command)
            }
            statusMessage = "Description ready"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func requireActiveWorkspace() throws -> TemporarySessionWorkspace {
        guard let activeWorkspace else {
            throw MotionSpecAppError.missingWorkspace
        }

        return activeWorkspace
    }

    private func moveCarouselFocus(by offset: Int) {
        let frames = visibleFrames
        guard !frames.isEmpty else {
            focusedFrameID = nil
            return
        }

        let currentID = focusedFrame?.id
        let currentIndex = currentID.flatMap { id in
            frames.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), frames.count - 1)
        focusedFrameID = frames[nextIndex].id
    }

    private func keepManualSelectionInsideVisibleTimeline() {
        guard frameSelectionMode == .manual else {
            return
        }

        let visibleFrameIDs = Set(visibleFrames.map(\.id))
        manualFrameIDs = manualFrameIDs.filter { visibleFrameIDs.contains($0) }
        reviewController.useManualFrameIDs(manualFrameIDs)
    }
}

enum MotionSpecAppError: LocalizedError {
    case missingWorkspace
    case missingGeminiAPIKey
    case noWindowAvailable

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "No active workspace"
        case .missingGeminiAPIKey:
            return "Add a Gemini API key first"
        case .noWindowAvailable:
            return "No capturable window found"
        }
    }
}
