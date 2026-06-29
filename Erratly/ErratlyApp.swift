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

class AppDelegate: NSObject, NSApplicationDelegate {
    var lastControlPressTime: Date?
    var previousApp: NSRunningApplication?
    var statusItem: NSStatusItem?
    var currentStatus: AppStatus = .loading

    static let languages: [String] = [
        "English", "French", "Spanish", "German", "Italian",
        "Portuguese", "Dutch", "Polish", "Russian",
        "Japanese", "Chinese", "Korean", "Arabic"
    ]

    var selectedLanguage: String? {
        get { UserDefaults.standard.string(forKey: "selectedLanguage") }
        set {
            if let lang = newValue {
                UserDefaults.standard.set(lang, forKey: "selectedLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedLanguage")
            }
        }
    }

    var strings: Strings { Strings.forLanguage(selectedLanguage) }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatus(.loading)
    }

    func setStatus(_ status: AppStatus) {
        DispatchQueue.main.async {
            self.currentStatus = status
            self.statusItem?.button?.title = status.symbol
            self.updateMenu(status: status)
        }
    }

    func handleSelectedText(_ text: String, previousClipboard: String?, app: NSRunningApplication) {
        setStatus(.processing)

        Task {
            do {
                let corrected = try await LLMService.shared.correctText(text, language: self.selectedLanguage)
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
