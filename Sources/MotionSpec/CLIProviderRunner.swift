import Foundation
import MotionSpecCore

struct CLIProviderRunner: Sendable {
    func run(_ command: ProcessCommand) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()

            process.executableURL = URL(filePath: command.executablePath)
            process.arguments = command.arguments
            process.standardOutput = output
            process.standardError = errorOutput
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(
                        throwing: CLIProviderRunnerError.nonZeroExit(
                            status: process.terminationStatus,
                            output: errorText.isEmpty ? text : errorText
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum CLIProviderRunnerError: LocalizedError {
    case nonZeroExit(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(status, output):
            return "CLI exited with status \(status): \(output)"
        }
    }
}
