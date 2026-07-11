import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    private enum HotKeyID: UInt32 {
        case startRegionCapture = 1
        case stopRecording = 2
    }

    private static let signature: OSType = 0x4D535043
    private static let modifiers = UInt32(cmdKey | optionKey | controlKey)

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var onStartRegionCapture: (@MainActor () -> Void)?
    private var onStopRecording: (@MainActor () -> Void)?

    func register(
        startRegionCapture: @escaping @MainActor () -> Void,
        stopRecording: @escaping @MainActor () -> Void
    ) {
        unregister()

        onStartRegionCapture = startRegionCapture
        onStopRecording = stopRecording

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )

        registerHotKey(
            id: .startRegionCapture,
            keyCode: UInt32(kVK_ANSI_R)
        )
        registerHotKey(
            id: .stopRecording,
            keyCode: UInt32(kVK_ANSI_S)
        )
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerHotKey(id: HotKeyID, keyCode: UInt32) {
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: id.rawValue
        )
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return
        }

        hotKeyRefs.append(hotKeyRef)
    }

    private func handle(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.signature else {
            return
        }

        switch HotKeyID(rawValue: hotKeyID.id) {
        case .startRegionCapture:
            Task { @MainActor in
                onStartRegionCapture?()
            }
        case .stopRecording:
            Task { @MainActor in
                onStopRecording?()
            }
        case nil:
            return
        }
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        let manager = Unmanaged<GlobalHotKeyManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            manager.handle(hotKeyID)
        }

        return noErr
    }
}
