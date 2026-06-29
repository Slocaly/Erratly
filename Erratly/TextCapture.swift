import Cocoa

extension AppDelegate {
    func getSelectedText() {
        guard let frontApp = self.previousApp else {
            print("⚠️ No previous app saved")
            return
        }

        let previousClipboard = NSPasteboard.general.string(forType: .string)

        print("🔍 Trying AX for: \(frontApp.localizedName ?? "unknown")")

        if let text = getTextViaAX(app: frontApp), !text.isEmpty {
            print("📋 Got text via AX: \(text)")
            handleSelectedText(text, previousClipboard: previousClipboard, app: frontApp)
            return
        }

        print("⚠️ AX failed, falling back to clipboard...")
        getTextViaClipboard(app: frontApp, previousClipboard: previousClipboard)
    }

    func getTextViaAX(app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusedResult == .success, let element = focusedElement else { return nil }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        guard textResult == .success, let text = selectedText as? String else { return nil }
        return text
    }

    func getTextViaClipboard(app: NSRunningApplication, previousClipboard: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        app.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let text = pasteboard.string(forType: .string), !text.isEmpty {
                    print("📋 Got text via clipboard: \(text)")
                    self.handleSelectedText(text, previousClipboard: previousClipboard, app: app)
                } else {
                    print("⚠️ Nothing selected")
                    pasteboard.clearContents()
                    if let previous = previousClipboard {
                        pasteboard.setString(previous, forType: .string)
                    }
                }
            }
        }
    }

    func replaceSelectedText(_ newText: String, app: NSRunningApplication, previousClipboard: String?) {
        if replaceTextViaAX(newText: newText, app: app) {
            print("✅ Replaced via AX")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let previous = previousClipboard {
                pasteboard.setString(previous, forType: .string)
            }
            return
        }
        print("⚠️ AX failed, falling back to clipboard paste...")
        replaceTextViaClipboard(newText: newText, app: app, previousClipboard: previousClipboard)
    }

    func replaceTextViaAX(newText: String, app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusedResult == .success, let element = focusedElement else { return false }

        let setResult = AXUIElementSetAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)

        return setResult == .success
    }

    func replaceTextViaClipboard(newText: String, app: NSRunningApplication, previousClipboard: String?) {
        let pasteboard = NSPasteboard.general

        app.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            pasteboard.setString(newText, forType: .string)

            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let previous = previousClipboard {
                    pasteboard.setString(previous, forType: .string)
                }
                print("📋 Clipboard restored to: \(previousClipboard ?? "empty")")
            }
        }
    }
}
