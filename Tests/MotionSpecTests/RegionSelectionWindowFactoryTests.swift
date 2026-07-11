import AppKit
import Testing
@testable import MotionSpec

@MainActor
@Suite
struct RegionSelectionWindowFactoryTests {
    @Test("Selection overlay window is not released by AppKit when closed")
    func selectionOverlayDisablesReleaseOnClose() {
        let window = RegionSelectionWindowFactory.makeWindow(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        )

        #expect(window.isReleasedWhenClosed == false)
        #expect(window.styleMask.contains(.borderless))
        #expect(window.isOpaque == false)
    }
}
