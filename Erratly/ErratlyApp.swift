import Cocoa
import Carbon
import ServiceManagement

@main
struct SpellFixApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

enum AppStatus {
    case loading, ready, processing, error

    var symbol: String {
        switch self {
        case .loading: return "⏳"
        case .ready: return "✦"
        case .processing: return "⟳"
        case .error: return "⚠️"
        }
    }

    var menuLabel: String {
        switch self {
        case .loading: return "Model is downloading..."
        case .ready: return "Erratly is ready to use"
        case .processing: return "Correcting text..."
        case .error: return "Failed to load model"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var lastControlPressTime: Date?
    var previousApp: NSRunningApplication?
    var statusItem: NSStatusItem?

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatus(.loading)
    }

    func setStatus(_ status: AppStatus) {
        DispatchQueue.main.async {
            self.statusItem?.button?.title = status.symbol
            self.updateMenu(status: status)
        }
    }

    func updateMenu(status: AppStatus) {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: status.menuLabel, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let modelItem = NSMenuItem(title: "Model: \(LLMService.modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Erratly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    func replaceTextViaAX(newText: String, app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusedResult == .success, let element = focusedElement else { return false }

        let setResult = AXUIElementSetAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)

        return setResult == .success
    }

    func replaceTextViaClipboard(newText: String, app: NSRunningApplication) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        app.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Set clipboard as late as possible, right before pasting
            pasteboard.clearContents()
            pasteboard.setString(newText, forType: .string)
            
            print("📋 Clipboard set to: \(pasteboard.string(forType: .string) ?? "empty")")

            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let previous = previousContent {
                    pasteboard.setString(previous, forType: .string)
                }
                print("📋 Clipboard restored to: \(pasteboard.string(forType: .string) ?? "empty")")
            }
        }
    }
    
    func getSelectedText() {
        guard let frontApp = self.previousApp else {
            print("⚠️ No previous app saved")
            return
        }

        // Save clipboard FIRST before anything touches it
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
    
    func handleSelectedText(_ text: String, previousClipboard: String?, app: NSRunningApplication) {
        setStatus(.processing)
        
        Task {
            do {
                let corrected = try await LLMService.shared.correctText(text)
                await MainActor.run {
                    self.replaceSelectedText(corrected, app: app, previousClipboard: previousClipboard)
                    self.setStatus(.ready)
                }
            } catch {
                print("❌ LLM error: \(error)")
                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if let previous = previousClipboard {
                        pasteboard.setString(previous, forType: .string)
                    }
                    self.setStatus(.error)
                }
            }
        }
    }

    func correctText(_ text: String) -> String {
        let checker = NSSpellChecker.shared
        checker.setLanguage(checker.language())
        
        var correctedText = text as NSString
        var offset = 0 // tracks how much the string length changes as we replace words

        var searchRange = NSRange(location: 0, length: correctedText.length)

        while searchRange.location < correctedText.length {
            // Find next misspelled word
            let misspelledRange = checker.checkSpelling(of: correctedText as String, startingAt: searchRange.location, language: checker.language(), wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

            // No more misspellings found
            if misspelledRange.location == NSNotFound { break }

            let misspelledWord = correctedText.substring(with: misspelledRange)
            print("🔴 Misspelled: \(misspelledWord)")

            // Get suggestions for this word
            if let suggestions = checker.guesses(forWordRange: misspelledRange, in: correctedText as String, language: checker.language(), inSpellDocumentWithTag: 0),
               let bestGuess = suggestions.first {
                print("✅ Suggestion: \(bestGuess)")
                correctedText = correctedText.replacingCharacters(in: misspelledRange, with: bestGuess) as NSString
                
                // Move past the corrected word
                searchRange.location = misspelledRange.location + bestGuess.utf16.count
            } else {
                // No suggestion, skip this word
                searchRange.location = misspelledRange.location + misspelledRange.length
            }

            searchRange.length = correctedText.length - searchRange.location
        }

        return correctedText as String
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        NSApp.setActivationPolicy(.accessory)

        try? SMAppService.mainApp.register()

        setupMenuBar()
        
        Task {
            do {
                try await LLMService.shared.loadModel()
                self.setStatus(.ready)
            } catch {
                print("❌ Failed to load model: \(error)")
                self.setStatus(.error)
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Only trigger if Control is the ONLY modifier pressed
            let isControlOnly = flags == .control

            if isControlOnly {
                let now = Date()

                if let lastPress = self.lastControlPressTime,
                   now.timeIntervalSince(lastPress) < 0.4 {
                    print("🎉 Double Control tap triggered!")
                    self.getSelectedText()
                    self.lastControlPressTime = nil
                } else {
                    self.previousApp = NSWorkspace.shared.frontmostApplication
                    self.lastControlPressTime = now
                }
            }
        }

        print("App is running, listening for double Control tap...")
    }
}
