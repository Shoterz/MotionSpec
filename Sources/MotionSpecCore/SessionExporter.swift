import Foundation

public struct TemporarySessionWorkspace: Sendable {
    public var baseDirectory: URL
    public var sessionID: String

    public var sessionDirectory: URL {
        baseDirectory.appending(path: sessionID, directoryHint: .isDirectory)
    }

    public init(baseDirectory: URL, sessionID: String = UUID().uuidString) throws {
        self.baseDirectory = baseDirectory
        self.sessionID = sessionID

        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
    }

    public func cleanup() throws {
        guard FileManager.default.fileExists(atPath: sessionDirectory.filePathString) else {
            return
        }

        try FileManager.default.removeItem(at: sessionDirectory)
    }
}

public struct ExportManifest: Equatable, Sendable {
    public var frameURLs: [URL]
    public var promptURL: URL

    public init(frameURLs: [URL], promptURL: URL) {
        self.frameURLs = frameURLs
        self.promptURL = promptURL
    }
}

public struct SessionExporter: Sendable {
    public init() { }

    public func export(
        frames: [MotionFrameCandidate],
        prompt: String,
        to directory: URL
    ) throws -> ExportManifest {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var exportedFrameURLs: [URL] = []

        for (index, frame) in frames.enumerated() {
            let fileName = "motion-frame-\(String(format: "%02d", index + 1)).png"
            let destination = directory.appending(path: fileName)

            if FileManager.default.fileExists(atPath: destination.filePathString) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: frame.imageURL, to: destination)
            exportedFrameURLs.append(destination)
        }

        let promptURL = directory.appending(path: "motion-prompt.txt")
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)

        return ExportManifest(frameURLs: exportedFrameURLs, promptURL: promptURL)
    }
}
