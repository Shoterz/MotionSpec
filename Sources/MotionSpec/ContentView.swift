import MotionSpecCore
import Observation
import SwiftUI

struct ContentView: View {
    @Bindable var model: MotionSpecAppModel

    var body: some View {
        NavigationSplitView {
            List {
                captureSection
                outputSection
                aiSection
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            ReviewPanel(model: model)
        }
        .frame(minWidth: 980, minHeight: 640)
        .task {
            model.refreshWindows()
        }
    }

    private var captureSection: some View {
        Section("Capture") {
            Picker("Mode", selection: $model.captureMode) {
                Label("Region", systemImage: "selection.pin.in.out")
                    .tag(CaptureMode.region)
                Label("Window", systemImage: "macwindow")
                    .tag(CaptureMode.window)
                Label("Screen", systemImage: "display")
                    .tag(CaptureMode.screen)
            }
            .pickerStyle(.segmented)

            if model.captureMode == .window {
                Picker("Window", selection: $model.selectedWindow) {
                    ForEach(model.availableWindows, id: \.windowID) { window in
                        Text(window.displayName).tag(Optional(window))
                    }
                }

                Button {
                    model.refreshWindows()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            HStack {
                Button {
                    model.startCapture()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartCapture)

                Button {
                    model.stopCapture()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!model.canStopRecording)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var outputSection: some View {
        Section("Output") {
            Picker("Frames", selection: $model.frameSelectionMode) {
                Text("Smart").tag(FrameSelectionMode.smartKeyframes)
                Text("Even").tag(FrameSelectionMode.evenIntervals)
                Text("Manual").tag(FrameSelectionMode.manual)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.frameSelectionMode) { _, mode in
                model.changeFrameSelectionMode(mode)
            }

            Picker("View", selection: $model.reviewDisplayMode) {
                Text("Grid").tag(ReviewDisplayMode.grid)
                Text("Carousel").tag(ReviewDisplayMode.carousel)
            }
            .pickerStyle(.segmented)

            Stepper(
                value: Binding(
                    get: { model.thumbnailColumns },
                    set: { model.setThumbnailColumns($0) }
                ),
                in: ReviewGridPreferences.minimumColumns...ReviewGridPreferences.maximumColumns
            ) {
                Label("Grid \(model.thumbnailColumns)", systemImage: "square.grid.3x3")
            }

            FrameStepPicker(spacing: $model.visibleFrameSpacing)

            if let startFrame = model.timelineStartFrame {
                HStack {
                    Label {
                        Text(startFrame.timestamp, format: .number.precision(.fractionLength(2)))
                    } icon: {
                        Image(systemName: "flag.fill")
                    }
                    Spacer()
                    Button {
                        model.resetTimelineStart()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear timeline start")
                    .accessibilityLabel("Clear timeline start")
                }
            }

            TextField("Note", text: $model.userNote, axis: .vertical)
                .lineLimit(2...4)

            Button {
                model.copyImagesAndPrompt()
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .disabled(!model.canUseOutputs)

            Button {
                model.exportFolder()
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.canUseOutputs)

            Button(role: .destructive) {
                model.clearSession()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!model.canClearSession || model.isRecording || model.isPreparingCapture)
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }

    private var aiSection: some View {
        Section("AI") {
            Picker("Provider", selection: $model.aiProvider) {
                Text("Gemini").tag(AIProvider.geminiAPI)
                Text("Codex CLI").tag(AIProvider.codexCLI)
                Text("Custom CLI").tag(AIProvider.customCLI)
            }

            if model.aiProvider == .geminiAPI {
                SecureField("Gemini API key", text: $model.geminiAPIKey)
                Button {
                    model.saveGeminiAPIKey()
                } label: {
                    Label("Save Key", systemImage: "key")
                }
            }

            if model.aiProvider == .customCLI {
                TextField("Command", text: $model.customCLICommand, axis: .vertical)
                    .lineLimit(2...4)
            }

            Button {
                model.describeWithAI()
            } label: {
                Label("Describe", systemImage: "sparkles")
            }
            .disabled(!model.canUseOutputs)
        }
    }
}

private struct ReviewPanel: View {
    @Bindable var model: MotionSpecAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            reviewContent
            descriptionPane
        }
        .padding(20)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 120), spacing: 12),
            count: model.thumbnailColumns
        )
    }

    private var thumbnailImageHeight: CGFloat {
        ReviewGridPreferences.imageHeight(forColumns: model.thumbnailColumns)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MotionSpec")
                    .font(.title2.weight(.semibold))
                if let review = model.currentReview {
                    Text("\(review.mode.rawValue.capitalized) · \(review.target.displayName) · \(review.duration, format: .number.precision(.fractionLength(2)))s")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        switch model.reviewDisplayMode {
        case .grid:
            frameGrid
        case .carousel:
            carousel
        }
    }

    private var frameGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: gridColumns,
                spacing: 12
            ) {
                ForEach(model.visibleFrames) { frame in
                    FrameThumbnail(
                        frame: frame,
                        imageHeight: thumbnailImageHeight,
                        isTimelineStart: model.timelineStartFrameID == frame.id,
                        isSelected: model.selectedFrames.contains { $0.id == frame.id }
                    ) {
                        model.reviewDisplayMode = .carousel
                        model.focusFrame(frame)
                    } toggleSelectionAction: {
                        model.toggleManualFrame(frame)
                    } setStartAction: {
                        model.setTimelineStart(frame)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var carousel: some View {
        if let frame = model.focusedFrame {
            HStack(spacing: 14) {
                Button {
                    model.showPreviousCarouselFrame()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isFirstVisibleFrame(frame))
                .help("Previous frame")
                .accessibilityLabel("Previous frame")

                VStack(spacing: 12) {
                    FrameImageView(frame: frame)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    carouselToolbar(for: frame)
                }

                Button {
                    model.showNextCarouselFrame()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isLastVisibleFrame(frame))
                .help("Next frame")
                .accessibilityLabel("Next frame")
            }
            .frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Frames", systemImage: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func carouselToolbar(for frame: MotionFrameCandidate) -> some View {
        HStack(spacing: 12) {
            Text(carouselPositionText(for: frame))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            FrameStepPicker(spacing: $model.visibleFrameSpacing)
                .frame(maxWidth: 280)

            Spacer()

            Button {
                model.setTimelineStart(frame)
            } label: {
                Image(systemName: model.timelineStartFrameID == frame.id ? "flag.fill" : "flag")
            }
            .buttonStyle(.bordered)
            .help("Use this frame as timeline start")
            .accessibilityLabel("Use this frame as timeline start")

            Button {
                model.toggleManualFrame(frame)
            } label: {
                Image(systemName: model.selectedFrames.contains { $0.id == frame.id } ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.bordered)
            .help("Toggle output frame")
            .accessibilityLabel("Toggle output frame")
        }
    }

    private func carouselPositionText(for frame: MotionFrameCandidate) -> String {
        let index = model.visibleFrames.firstIndex { $0.id == frame.id } ?? 0
        let timestamp = frame.timestamp.formatted(.number.precision(.fractionLength(2)))

        return "\(index + 1) of \(model.visibleFrames.count) · \(timestamp)s"
    }

    private func isFirstVisibleFrame(_ frame: MotionFrameCandidate) -> Bool {
        model.visibleFrames.first?.id == frame.id
    }

    private func isLastVisibleFrame(_ frame: MotionFrameCandidate) -> Bool {
        model.visibleFrames.last?.id == frame.id
    }

    @ViewBuilder
    private var descriptionPane: some View {
        if !model.aiDescription.isEmpty {
            ScrollView {
                Text(model.aiDescription)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
        }
    }
}

private struct FrameThumbnail: View {
    var frame: MotionFrameCandidate
    var imageHeight: CGFloat
    var isTimelineStart: Bool
    var isSelected: Bool
    var openAction: () -> Void
    var toggleSelectionAction: () -> Void
    var setStartAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: openAction) {
                FrameImageView(frame: frame)
                    .frame(height: imageHeight)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Open frame in carousel")
            .accessibilityLabel("Open frame in carousel")

            HStack {
                Text(frame.timestamp, format: .number.precision(.fractionLength(2)))
                Spacer()

                Button(action: setStartAction) {
                    Image(systemName: isTimelineStart ? "flag.fill" : "flag")
                        .foregroundStyle(isTimelineStart ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Use this frame as timeline start")
                .accessibilityLabel("Use this frame as timeline start")

                Button(action: toggleSelectionAction) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle output frame")
                .accessibilityLabel("Toggle output frame")
            }
            .font(.caption)
        }
        .padding(6)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var backgroundStyle: Color {
        if isTimelineStart {
            return Color.orange.opacity(0.16)
        }

        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        return Color.secondary.opacity(0.08)
    }
}

private struct FrameImageView: View {
    var frame: MotionFrameCandidate

    var body: some View {
        if let image = NSImage(contentsOf: frame.imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FrameStepPicker: View {
    @Binding var spacing: TimeInterval

    var body: some View {
        Picker("Step", selection: $spacing) {
            Text("All").tag(TimeInterval(0))
            Text("0.05").tag(TimeInterval(0.05))
            Text("0.10").tag(TimeInterval(0.10))
            Text("0.20").tag(TimeInterval(0.20))
            Text("0.50").tag(TimeInterval(0.50))
        }
        .pickerStyle(.segmented)
    }
}

private extension WindowCaptureTarget {
    var displayName: String {
        let titleText = title.isEmpty ? "Untitled" : title
        return "\(ownerName) - \(titleText)"
    }
}
