import AppKit
import Foundation
import MotionSpecCore

@MainActor
final class RegionSelectionController {
    private var activeController: RegionSelectionWindowController?

    func selectRegion() async throws -> CaptureRegion {
        try await withCheckedThrowingContinuation { continuation in
            let controller = RegionSelectionWindowController { [weak self] result in
                self?.activeController = nil
                continuation.resume(with: result)
            }
            activeController = controller
            controller.show()
        }
    }
}

@MainActor
private final class RegionSelectionWindowController {
    private let completion: (Result<CaptureRegion, Error>) -> Void
    private var window: NSWindow?
    private var completionGate = OneShotGate()

    init(completion: @escaping (Result<CaptureRegion, Error>) -> Void) {
        self.completion = completion
    }

    func show() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let selectionView = RegionSelectionView(frame: frame) { [weak self] result in
            self?.finish(with: result)
        }
        let window = RegionSelectionWindowFactory.makeWindow(
            frame: frame,
            contentView: selectionView
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func finish(with result: Result<CaptureRegion, Error>) {
        guard completionGate.accept() else {
            return
        }

        let window = window

        DispatchQueue.main.async { [completion] in
            window?.orderOut(nil)
            window?.close()
            completion(result)
        }
    }
}

private final class RegionSelectionView: NSView {
    private let completion: (Result<CaptureRegion, Error>) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(frame: CGRect, completion: @escaping (Result<CaptureRegion, Error>) -> Void) {
        self.completion = completion
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let rect = selectedRect

        guard rect.width >= 24, rect.height >= 24 else {
            completion(.failure(RegionSelectionError.tooSmall))
            return
        }

        let screenRect = convertToScreen(rect)
        completion(
            .success(
                CaptureRegion(
                    x: screenRect.minX,
                    y: screenRect.minY,
                    width: screenRect.width,
                    height: screenRect.height
                )
            )
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(.failure(RegionSelectionError.cancelled))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: selectedRect)
        path.lineWidth = 2
        path.stroke()
    }

    private var selectedRect: CGRect {
        guard let startPoint, let currentPoint else {
            return .zero
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func convertToScreen(_ rect: CGRect) -> CGRect {
        guard let window else {
            return rect
        }

        return window.convertToScreen(rect)
    }
}

private enum RegionSelectionError: LocalizedError {
    case cancelled
    case tooSmall

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Region selection cancelled"
        case .tooSmall:
            return "Select a larger region"
        }
    }
}
