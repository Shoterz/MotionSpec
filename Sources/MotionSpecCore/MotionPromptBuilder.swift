import Foundation

public struct MotionPromptBuilder: Sendable {
    public init() { }

    public func buildPrompt(
        for review: CaptureReviewSession,
        selectedFrames: [MotionFrameCandidate],
        userNote: String? = nil
    ) -> String {
        var lines = [
            "You are describing a UI animation or transition for a builder.",
            "Use the attached frames as a chronological sequence and write a precise implementation-ready motion spec.",
            "",
            "Capture context:",
            "- Mode: \(review.mode.rawValue)",
            "- Target: \(review.target.displayName)",
            "- Duration: \(format(seconds: review.duration))s"
        ]

        if let userNote, !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- User note: \(userNote)")
        }

        lines.append(contentsOf: [
            "",
            "Frames:",
        ])

        for (index, frame) in selectedFrames.sorted(by: { $0.timestamp < $1.timestamp }).enumerated() {
            lines.append("- Frame \(index + 1) at \(format(seconds: frame.timestamp))s")
        }

        lines.append(contentsOf: [
            "",
            "Describe:",
            "- The before and after UI states.",
            "- The trigger or interaction that appears to start the motion.",
            "- The motion path, hierarchy changes, opacity, scale, blur, color, and layout changes.",
            "- The likely timing, duration, easing, staging, and whether elements animate together or sequentially.",
            "- Concise implementation guidance a frontend or native app builder could use."
        ])

        return lines.joined(separator: "\n")
    }

    private func format(seconds: TimeInterval) -> String {
        String(format: "%.2f", seconds)
    }
}
