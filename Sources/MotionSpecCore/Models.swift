import Foundation

public enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case region
    case window
    case screen
}

public enum FrameSelectionMode: String, CaseIterable, Codable, Sendable {
    case smartKeyframes
    case evenIntervals
    case manual
}

public enum OutputAction: String, CaseIterable, Codable, Sendable {
    case copyImagesAndPrompt
    case exportFolder
    case describeWithAI
}

public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case geminiAPI
    case codexCLI
    case customCLI
}

public struct CaptureRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WindowCaptureTarget: Codable, Equatable, Hashable, Sendable {
    public var windowID: UInt32
    public var ownerName: String
    public var title: String

    public init(windowID: UInt32, ownerName: String, title: String) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.title = title
    }
}

public struct DisplayCaptureTarget: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var name: String

    public init(displayID: UInt32, name: String) {
        self.displayID = displayID
        self.name = name
    }
}

public enum CaptureTarget: Codable, Equatable, Sendable {
    case region(CaptureRegion)
    case window(WindowCaptureTarget)
    case screen(DisplayCaptureTarget)

    public var mode: CaptureMode {
        switch self {
        case .region:
            return .region
        case .window:
            return .window
        case .screen:
            return .screen
        }
    }

    public var displayName: String {
        switch self {
        case let .region(region):
            return "region \(Int(region.width))x\(Int(region.height)) at \(Int(region.x)),\(Int(region.y))"
        case let .window(window):
            return "\(window.ownerName) - \(window.title)"
        case let .screen(display):
            return display.name
        }
    }
}

public struct MotionFrameCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: TimeInterval
    public var imageURL: URL
    public var changeScore: Double

    public init(
        id: String,
        timestamp: TimeInterval,
        imageURL: URL,
        changeScore: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.changeScore = changeScore
    }
}

public struct CaptureReviewSession: Codable, Equatable, Sendable {
    public var mode: CaptureMode
    public var target: CaptureTarget
    public var recordingURL: URL
    public var duration: TimeInterval
    public var frames: [MotionFrameCandidate]

    public init(
        mode: CaptureMode,
        target: CaptureTarget,
        recordingURL: URL,
        duration: TimeInterval,
        frames: [MotionFrameCandidate]
    ) {
        self.mode = mode
        self.target = target
        self.recordingURL = recordingURL
        self.duration = duration
        self.frames = frames
    }
}

extension URL {
    var filePathString: String {
        if #available(macOS 13.0, *) {
            return path(percentEncoded: false)
        }

        return path
    }
}
