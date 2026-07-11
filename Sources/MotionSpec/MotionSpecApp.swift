import SwiftUI

@main
struct MotionSpecApp: App {
    @State private var model = MotionSpecAppModel()
    @State private var hotKeyManager = GlobalHotKeyManager()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    hotKeyManager.register {
                        model.startCapture(.region)
                    } stopRecording: {
                        model.stopCapture()
                    }
                }
        }
        .commands {
            CommandMenu("Capture") {
                Button("Start Region Capture") {
                    model.startCapture(.region)
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .control])
                .disabled(!model.canStartCapture)

                Button("Stop Recording") {
                    model.stopCapture()
                }
                .keyboardShortcut("s", modifiers: [.command, .option, .control])
                .disabled(!model.canStopRecording)

                Divider()

                Button("Clear Session") {
                    model.clearSession()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!model.canClearSession || model.isRecording || model.isPreparingCapture)
            }

            CommandMenu("Review") {
                Button("Previous Frame") {
                    model.showPreviousCarouselFrame()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(model.reviewDisplayMode != .carousel || model.focusedFrame == nil)

                Button("Next Frame") {
                    model.showNextCarouselFrame()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(model.reviewDisplayMode != .carousel || model.focusedFrame == nil)

                Button("Toggle Focused Frame") {
                    model.toggleFocusedFrameSelection()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.reviewDisplayMode != .carousel || model.focusedFrame == nil)
            }
        }

        MenuBarExtra("MotionSpec", systemImage: "rectangle.dashed") {
            Button("Capture Region") {
                model.startCapture(.region)
            }
            .disabled(!model.canStartCapture)
            Button("Capture Window") {
                model.startCapture(.window)
            }
            .disabled(!model.canStartCapture)
            Button("Capture Screen") {
                model.startCapture(.screen)
            }
            .disabled(!model.canStartCapture)
            Divider()
            Button("Stop Recording") {
                model.stopCapture()
            }
            .disabled(!model.canStopRecording)
            Divider()
            Button("Copy Frames and Prompt") {
                model.copyImagesAndPrompt()
            }
            .disabled(!model.canUseOutputs)
            Button("Clear Session") {
                model.clearSession()
            }
            .disabled(!model.canClearSession || model.isRecording || model.isPreparingCapture)
        }
        .menuBarExtraStyle(.menu)
    }
}
