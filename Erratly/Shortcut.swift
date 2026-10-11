import Cocoa
import Carbon

/// A custom key combination that triggers a correction. When no custom
/// shortcut is set, Erratly falls back to the double Control tap.
nonisolated struct KeyShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt  // NSEvent.ModifierFlags raw value (⌘⌥⌃⇧ only)
    let keyLabel: String

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        let flags = modifierFlags
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Returns nil when the event has no ⌘, ⌥ or ⌃ — a bare key (or Shift+key)
    /// would hijack normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevantModifiers)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = flags.rawValue
        self.keyLabel = Self.label(for: event)
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let chars = event.characters(byApplyingModifiers: []) ?? ""
            return chars.isEmpty ? "#\(event.keyCode)" : chars.uppercased()
        }
    }
}

/// Registers the custom shortcut as a Carbon global hot key. A second hot key
/// with Shift added mirrors the double ⌃⇧ behaviour (flip the review panel),
/// unless the shortcut already uses Shift.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    /// Called with `true` when the Shift variant fired.
    var onTrigger: ((Bool) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var isSuspended = false

    private static let signature: OSType = 0x4552_5254  // "ERRT"
    private static let plainID: UInt32 = 1
    private static let shiftID: UInt32 = 2

    /// Re-reads the saved shortcut and (un)registers hot keys accordingly.
    func reload() {
        unregisterAll()
        guard !isSuspended, let shortcut = AppSettings.shared.shortcut else { return }
        installHandlerIfNeeded()

        register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, id: Self.plainID)
        if !shortcut.modifierFlags.contains(.shift) {
            register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers | UInt32(shiftKey), id: Self.shiftID)
        }
    }

    /// Temporarily disables hot keys, e.g. while the settings window records a
    /// new shortcut — otherwise re-typing the current one would trigger it.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        reload()
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        } else {
            print("⚠️ Failed to register hot key (status \(status))")
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &handlerRef)
    }

    fileprivate func handle(id: UInt32) {
        onTrigger?(id == Self.shiftID)
    }
}

// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
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
    guard status == noErr else { return status }
    MainActor.assumeIsolated {
        HotkeyManager.shared.handle(id: hotKeyID.id)
    }
    return noErr
}
