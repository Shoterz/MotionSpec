import Foundation

public struct ProcessCommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct GeminiRequestBuilder: Sendable {
    public var model: String

    public init(model: String) {
        self.model = model
    }

    public func makeRequestBody(
        prompt: String,
        frames: [MotionFrameCandidate]
    ) throws -> Data {
        var input: [[String: String]] = [
            [
                "type": "text",
                "text": prompt
            ]
        ]

        for frame in frames {
            let data = try Data(contentsOf: frame.imageURL)
            input.append([
                "type": "image",
                "data": data.base64EncodedString(),
                "mime_type": mimeType(for: frame.imageURL)
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "input": input
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        default:
            return "image/png"
        }
    }
}

public struct CodexCLICommandBuilder: Sendable {
    public var executablePath: String

    public init(executablePath: String = "codex") {
        self.executablePath = executablePath
    }

    public func makeCommand(prompt: String, frames: [MotionFrameCandidate]) -> ProcessCommand {
        var arguments = [
            "exec",
            "--skip-git-repo-check"
        ]

        for frame in frames {
            arguments.append("--image")
            arguments.append(frame.imageURL.filePathString)
        }

        arguments.append(prompt)

        return ProcessCommand(executablePath: executablePath, arguments: arguments)
    }
}

public enum CustomCLICommandBuilderError: Error, Equatable, Sendable {
    case emptyTemplate
    case unterminatedQuote
}

public struct CustomCLICommandBuilder: Sendable {
    public init() { }

    public func makeCommand(
        template: String,
        promptFile: URL,
        frames: [MotionFrameCandidate]
    ) throws -> ProcessCommand {
        let tokens = try tokenize(template)

        guard let executablePath = tokens.first else {
            throw CustomCLICommandBuilderError.emptyTemplate
        }

        var arguments: [String] = []

        for token in tokens.dropFirst() {
            if token == "{{frames}}" {
                arguments.append(contentsOf: frames.map { $0.imageURL.filePathString })
            } else if token.hasPrefix("{{frame"), token.hasSuffix("}}") {
                if let frame = frame(for: token, frames: frames) {
                    arguments.append(frame.imageURL.filePathString)
                }
            } else {
                arguments.append(
                    token.replacingOccurrences(
                        of: "{{promptFile}}",
                        with: promptFile.filePathString
                    )
                )
            }
        }

        return ProcessCommand(executablePath: executablePath, arguments: arguments)
    }

    private func frame(
        for token: String,
        frames: [MotionFrameCandidate]
    ) -> MotionFrameCandidate? {
        let numberText = token
            .replacingOccurrences(of: "{{frame", with: "")
            .replacingOccurrences(of: "}}", with: "")

        guard let oneBasedIndex = Int(numberText) else {
            return nil
        }

        let index = oneBasedIndex - 1
        guard frames.indices.contains(index) else {
            return nil
        }

        return frames[index]
    }

    private func tokenize(_ template: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var activeQuote: Character?

        for character in template {
            if let quote = activeQuote {
                if character == quote {
                    activeQuote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                activeQuote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if activeQuote != nil {
            throw CustomCLICommandBuilderError.unterminatedQuote
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
