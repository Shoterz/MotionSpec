import Foundation
import MotionSpecCore
@preconcurrency import ScreenCaptureKit

struct NativeCaptureTargetResolver: Sendable {
    func availableWindows() async throws -> [WindowCaptureTarget] {
        let content = try await SCShareableContent.current

        return content.windows
            .filter { $0.isOnScreen && $0.windowLayer == 0 }
            .compactMap { window in
                guard let application = window.owningApplication else {
                    return nil
                }

                return WindowCaptureTarget(
                    windowID: window.windowID,
                    ownerName: application.applicationName,
                    title: window.title ?? ""
                )
            }
            .sorted {
                if $0.ownerName == $1.ownerName {
                    return $0.title < $1.title
                }

                return $0.ownerName < $1.ownerName
            }
    }

    func mainDisplayTarget() async throws -> CaptureTarget {
        let content = try await SCShareableContent.current
        let mainDisplayID = CGMainDisplayID()
        let display = content.displays.first { $0.displayID == mainDisplayID }
            ?? content.displays.first

        guard let display else {
            throw NativeCaptureTargetResolverError.noDisplayAvailable
        }

        return .screen(
            DisplayCaptureTarget(
                displayID: display.displayID,
                name: "Display \(display.displayID)"
            )
        )
    }
}

enum NativeCaptureTargetResolverError: LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No capturable display found"
        }
    }
}
