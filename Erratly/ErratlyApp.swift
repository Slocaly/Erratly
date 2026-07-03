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
    var lastControlShiftPressTime: Date?
    var isShiftTrigger = false
    var previousApp: NSRunningApplication?
    var statusItem: NSStatusItem?
    var currentStatus: AppStatus = .loading
    var diffPanel: DiffPanel?

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

    var showDiffPanel: Bool {
        get { UserDefaults.standard.object(forKey: "showDiffPanel") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showDiffPanel") }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatus(.loading)
    }

    func setStatus(_ status: AppStatus) {
        DispatchQueue.main.async {
            self.currentStatus = status
            self.statusItem?.button?.title = status.symbol
            self.updateMenu(status: status)

            if status != .processing {
                LoadingOverlay.shared.hide()
            }
        }
    }

    func handleSelectedText(_ text: String, previousClipboard: String?, selectionBounds: CGRect?, app: NSRunningApplication) {
        let effectiveShowDiff = isShiftTrigger ? !showDiffPanel : showDiffPanel
        isShiftTrigger = false
        let examples = CorrectionHistory.shared.pairs
        setStatus(.processing)
        LoadingOverlay.shared.show(near: selectionBounds)

        Task {
            do {
                let corrected = try await LLMService.shared.correctText(text, language: self.selectedLanguage, examples: examples)
                await MainActor.run {
                    self.setStatus(.ready)

                    guard corrected != text else {
                        Analytics.correctionNoChange()
                        return
                    }

                    guard effectiveShowDiff else {
                        CorrectionHistory.shared.record(original: text, corrected: corrected)
                        self.replaceSelectedText(corrected, app: app, previousClipboard: previousClipboard)
                        Analytics.correctionApplied(language: self.selectedLanguage)
                        return
                    }

                    self.diffPanel?.window?.close()
                    NSApp.activate(ignoringOtherApps: true)

                    self.diffPanel = DiffPanel(
                        original: text,
                        corrected: corrected,
                        selectionBounds: selectionBounds,
                        onAccept: { [weak self] in
                            CorrectionHistory.shared.record(original: text, corrected: corrected)
                            self?.replaceSelectedText(corrected, app: app, previousClipboard: previousClipboard)
                            Analytics.correctionAccepted(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        },
                        onCancel: { [weak self] in
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            if let previous = previousClipboard {
                                pasteboard.setString(previous, forType: .string)
                            }
                            Analytics.correctionRejected(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        }
                    )
                    self.diffPanel?.showWindow(nil)
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
        Analytics.initialize()

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
            let now = Date()

            if flags == .control {
                if let lastPress = self.lastControlPressTime,
                   now.timeIntervalSince(lastPress) < 0.4 {
                    print("🎉 Double Control triggered!")
                    self.isShiftTrigger = false
                    self.getSelectedText()
                    self.lastControlPressTime = nil
                } else {
                    self.previousApp = NSWorkspace.shared.frontmostApplication
                    self.lastControlPressTime = now
                }
            } else if flags == [.control, .shift] {
                if let lastPress = self.lastControlShiftPressTime,
                   now.timeIntervalSince(lastPress) < 0.4 {
                    print("🎉 Double Control+Shift triggered!")
                    self.isShiftTrigger = true
                    self.getSelectedText()
                    self.lastControlShiftPressTime = nil
                } else {
                    self.previousApp = NSWorkspace.shared.frontmostApplication
                    self.lastControlShiftPressTime = now
                }
            }
        }

        print("App is running, listening for double Control tap...")
    }
}
