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
}

struct Strings {
    let loading: String
    let ready: String
    let processing: String
    let error: String
    let modelPrefix: String
    let language: String
    let autoDetect: String
    let quit: String

    func label(for status: AppStatus) -> String {
        switch status {
        case .loading: return loading
        case .ready: return ready
        case .processing: return processing
        case .error: return error
        }
    }

    static func forLanguage(_ language: String?) -> Strings {
        switch language {
        case "French":
            return Strings(loading: "Chargement du modèle...", ready: "Erratly est prêt", processing: "Correction en cours...", error: "Impossible de charger le modèle", modelPrefix: "Modèle", language: "Langue", autoDetect: "Détection automatique", quit: "Quitter Erratly")
        case "Spanish":
            return Strings(loading: "Cargando modelo...", ready: "Erratly está listo", processing: "Corrigiendo texto...", error: "Error al cargar el modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detección automática", quit: "Salir de Erratly")
        case "German":
            return Strings(loading: "Modell wird geladen...", ready: "Erratly ist bereit", processing: "Text wird korrigiert...", error: "Modell konnte nicht geladen werden", modelPrefix: "Modell", language: "Sprache", autoDetect: "Automatisch erkennen", quit: "Erratly beenden")
        case "Italian":
            return Strings(loading: "Caricamento modello...", ready: "Erratly è pronto", processing: "Correzione in corso...", error: "Impossibile caricare il modello", modelPrefix: "Modello", language: "Lingua", autoDetect: "Rilevamento automatico", quit: "Esci da Erratly")
        case "Portuguese":
            return Strings(loading: "Carregando modelo...", ready: "Erratly está pronto", processing: "Corrigindo texto...", error: "Falha ao carregar o modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detecção automática", quit: "Sair do Erratly")
        case "Dutch":
            return Strings(loading: "Model wordt geladen...", ready: "Erratly is klaar", processing: "Tekst wordt gecorrigeerd...", error: "Laden van model mislukt", modelPrefix: "Model", language: "Taal", autoDetect: "Automatisch detecteren", quit: "Erratly afsluiten")
        case "Polish":
            return Strings(loading: "Ładowanie modelu...", ready: "Erratly jest gotowy", processing: "Korygowanie tekstu...", error: "Nie udało się załadować modelu", modelPrefix: "Model", language: "Język", autoDetect: "Automatyczne wykrywanie", quit: "Zamknij Erratly")
        case "Russian":
            return Strings(loading: "Загрузка модели...", ready: "Erratly готов к работе", processing: "Исправление текста...", error: "Не удалось загрузить модель", modelPrefix: "Модель", language: "Язык", autoDetect: "Автоопределение", quit: "Выйти из Erratly")
        case "Japanese":
            return Strings(loading: "モデルを読み込み中...", ready: "Erratly は使用可能です", processing: "テキストを修正中...", error: "モデルの読み込みに失敗しました", modelPrefix: "モデル", language: "言語", autoDetect: "自動検出", quit: "Erratly を終了")
        case "Chinese":
            return Strings(loading: "正在加载模型...", ready: "Erratly 已就绪", processing: "正在纠正文本...", error: "模型加载失败", modelPrefix: "模型", language: "语言", autoDetect: "自动检测", quit: "退出 Erratly")
        case "Korean":
            return Strings(loading: "모델 로딩 중...", ready: "Erratly 사용 준비 완료", processing: "텍스트 수정 중...", error: "모델 로드 실패", modelPrefix: "모델", language: "언어", autoDetect: "자동 감지", quit: "Erratly 종료")
        case "Arabic":
            return Strings(loading: "جارٍ تحميل النموذج...", ready: "Erratly جاهز للاستخدام", processing: "جارٍ تصحيح النص...", error: "فشل في تحميل النموذج", modelPrefix: "النموذج", language: "اللغة", autoDetect: "الكشف التلقائي", quit: "إنهاء Erratly")
        default:
            return Strings(loading: "Model is downloading...", ready: "Erratly is ready to use", processing: "Correcting text...", error: "Failed to load model", modelPrefix: "Model", language: "Language", autoDetect: "Auto-detect", quit: "Quit Erratly")
        }
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

    func updateMenu(status: AppStatus) {
        let s = strings
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: s.label(for: status), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let modelItem = NSMenuItem(title: "\(s.modelPrefix): \(LLMService.modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: s.language, action: nil, keyEquivalent: "")
        languageItem.submenu = buildLanguageSubmenu(strings: s)
        menu.addItem(languageItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: s.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    func buildLanguageSubmenu(strings s: Strings) -> NSMenu {
        let submenu = NSMenu(title: s.language)

        let autoItem = NSMenuItem(title: s.autoDetect, action: #selector(selectLanguage(_:)), keyEquivalent: "")
        autoItem.representedObject = nil
        autoItem.state = selectedLanguage == nil ? .on : .off
        autoItem.target = self
        submenu.addItem(autoItem)

        submenu.addItem(.separator())

        for lang in AppDelegate.languages {
            let item = NSMenuItem(title: lang, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang
            item.state = selectedLanguage == lang ? .on : .off
            item.target = self
            submenu.addItem(item)
        }

        return submenu
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        selectedLanguage = sender.representedObject as? String
        updateMenu(status: currentStatus)
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

    func correctText(_ text: String) -> String {
        let checker = NSSpellChecker.shared
        checker.setLanguage(checker.language())
        
        var correctedText = text as NSString

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
