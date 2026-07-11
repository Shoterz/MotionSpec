import AppKit
import MotionSpecCore

struct ClipboardWriter: Sendable {
    func copy(frames: [MotionFrameCandidate], prompt: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = [prompt as NSString]
        objects.append(contentsOf: frames.map { $0.imageURL as NSURL })
        objects.append(contentsOf: frames.compactMap { NSImage(contentsOf: $0.imageURL) })

        pasteboard.writeObjects(objects)
    }
}
