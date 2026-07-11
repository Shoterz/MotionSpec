import Foundation
import MotionSpecCore

struct GeminiMotionDescriptionClient: Sendable {
    func describe(
        prompt: String,
        frames: [MotionFrameCandidate],
        apiKey: String
    ) async throws -> String {
        let body = try GeminiRequestBuilder(model: "gemini-3.5-flash")
            .makeRequestBody(prompt: prompt, frames: frames)

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown Gemini error"
            throw GeminiMotionDescriptionClientError.requestFailed(text)
        }

        return try parseOutputText(from: data)
    }

    private func parseOutputText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)

        if let dictionary = object as? [String: Any],
           let outputText = dictionary["output_text"] as? String {
            return outputText
        }

        if let dictionary = object as? [String: Any],
           let text = dictionary["text"] as? String {
            return text
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum GeminiMotionDescriptionClientError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            return "Gemini request failed: \(message)"
        }
    }
}
