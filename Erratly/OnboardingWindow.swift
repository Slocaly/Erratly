import Cocoa
import Combine
import SwiftUI

/// First-launch walkthrough: language, backend (with the model download),
/// Accessibility, a practice run of the shortcut, then a "ready" screen.
final class OnboardingWindow: NSWindowController, NSWindowDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Erratly"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(SettingsTheme.paper)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let view = OnboardingView(
            appDelegate: appDelegate,
            backendState: appDelegate.backendState,
            onFinish: { [weak self] in
                AppSettings.shared.hasCompletedOnboarding = true
                self?.window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Closing early leaves hasCompletedOnboarding false, so the guide comes
    // back on next launch; nothing is downloaded unless the user asked for it.
    func windowWillClose(_ notification: Notification) {
        appDelegate?.onboardingWindow = nil
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case language, backend, accessibility, tryIt, ready
}

private struct OnboardingView: View {
    let appDelegate: AppDelegate
    @ObservedObject var backendState: BackendState
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .language
    @State private var language: String?
    @State private var backend: Backend
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var modelName: String
    /// The backend whose load was started from (or before) this guide; nil
    /// until the user clicks "Download model" or continues with Remote.
    @State private var startedBackend: Backend?
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var sampleText = ""
    @State private var practiceDone = false
    @FocusState private var editorFocused: Bool

    private let accessibilityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(appDelegate: AppDelegate, backendState: BackendState, onFinish: @escaping () -> Void) {
        self.appDelegate = appDelegate
        self.backendState = backendState
        self.onFinish = onFinish
        let settings = AppSettings.shared
        _language = State(initialValue: appDelegate.selectedLanguage)
        _backend = State(initialValue: settings.backend)
        _baseURL = State(initialValue: settings.remoteBaseURL)
        _apiKey = State(initialValue: settings.remoteAPIKey ?? "")
        _modelName = State(initialValue: settings.remoteModelName)
        _startedBackend = State(initialValue: backendState.status == .needsSetup ? nil : settings.backend)
    }

    private var s: OnboardingStrings { .forLanguage(language) }

    private var shortcutLabel: String {
        AppSettings.shared.shortcut?.displayString ?? "⌃ ⌃"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 26)

            Group {
                switch step {
                case .language: languageStep
                case .backend: backendStep
                case .accessibility: accessibilityStep
                case .tryIt: tryStep
                case .ready: readyStep
                }
            }
            .id(step)
            .transition(.opacity)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 460, height: 580)
        .background(RuledPaper())
        .preferredColorScheme(.light)
        .onReceive(accessibilityTimer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onChange(of: backendState.inAppCorrections) {
            if step == .tryIt { practiceDone = true }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 14) {
            Image("AppIconRound")
                .resizable()
                .frame(width: 48, height: 48)
                .shadow(color: SettingsTheme.ink.opacity(0.2), radius: 6, y: 3)
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? SettingsTheme.accent : SettingsTheme.ink.opacity(item.rawValue < step.rawValue ? 0.6 : 0.2))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
        }
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(SettingsTheme.mono(17, .bold))
                .foregroundStyle(SettingsTheme.ink)
            Text(subtitle)
                .font(SettingsTheme.mono(12))
                .foregroundStyle(SettingsTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 22)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .language && step != .ready {
                Button(s.back) { go(by: -1) }
                    .buttonStyle(QuietButtonStyle())
            }
            Spacer()
            if showsSkip {
                Button(s.skip) { go(by: 1) }
                    .buttonStyle(.plain)
                    .font(SettingsTheme.mono(11, .bold))
                    .foregroundStyle(SettingsTheme.muted)
                    .underline()
            }
            Button(step == .ready ? s.start : s.next) { primaryAction() }
                .buttonStyle(AccentButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
                // Return must stay a newline in the practice field.
                .keyboardShortcut(step == .tryIt ? nil : .defaultAction)
        }
    }

    private var showsSkip: Bool {
        switch step {
        case .accessibility: return !accessibilityGranted
        case .tryIt: return !practiceDone
        default: return false
        }
    }

    private var remoteFieldsFilled: Bool {
        [baseURL, apiKey, modelName].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var canContinue: Bool {
        switch step {
        case .language, .ready: return true
        case .backend: return backend == .local ? startedBackend == .local : remoteFieldsFilled
        case .accessibility: return accessibilityGranted
        case .tryIt: return practiceDone
        }
    }

    private func go(by offset: Int) {
        guard let target = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        if target == .tryIt && !practiceDone {
            sampleText = OnboardingStrings.sampleSentence(for: language)
        }
        withAnimation(.easeInOut(duration: 0.2)) { step = target }
    }

    private func primaryAction() {
        switch step {
        case .language:
            appDelegate.selectedLanguage = language
            appDelegate.updateMenu(status: appDelegate.currentStatus)
        case .backend where backend == .remote:
            saveRemoteSettings()
        case .ready:
            onFinish()
            return
        default:
            break
        }
        go(by: 1)
    }

    // MARK: - Language

    private var languageStep: some View {
        VStack(spacing: 0) {
            title(s.languageTitle, s.languageSubtitle)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                languageChip(nil)
                ForEach(AppDelegate.languages, id: \.self) { languageChip($0) }
            }
        }
    }

    private func languageChip(_ value: String?) -> some View {
        let selected = language == value
        let label = value.map { OnboardingStrings.nativeName(of: $0) } ?? s.autoDetect
        return Text(label)
            .font(SettingsTheme.mono(12, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(selected ? SettingsTheme.paper : SettingsTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 2).fill(selected ? SettingsTheme.ink : SettingsTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink.opacity(selected ? 1 : 0.3), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { language = value }
            }
    }

    // MARK: - Backend

    private var backendStep: some View {
        VStack(spacing: 0) {
            title(s.backendTitle, s.backendSubtitle)
            PillSwitch(selection: $backend, options: [(.local, s.local), (.remote, s.remote)])
                .padding(.bottom, 22)
            if backend == .local {
                localPanel
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    StyledField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: $baseURL)
                    StyledField(label: "API Key", placeholder: "sk-…", text: $apiKey, secure: true)
                    StyledField(label: "Model Name", placeholder: "gpt-4o-mini", text: $modelName)
                    Text(s.remoteHint)
                        .font(SettingsTheme.mono(10))
                        .foregroundStyle(SettingsTheme.muted)
                }
            }
        }
        .onAppear { loadCachedModelIfNeeded() }
        .onChange(of: backend) { loadCachedModelIfNeeded() }
    }

    /// An already-downloaded model needs no confirmation: nothing will be
    /// fetched, so load it straight away instead of offering "Download model".
    private func loadCachedModelIfNeeded() {
        guard backend == .local, startedBackend != .local, LocalCorrectionProvider.isDownloaded else { return }
        startLocalDownload()
    }

    private var localPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.localPoints, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("✦").foregroundStyle(SettingsTheme.accent)
                        Text(point).foregroundStyle(SettingsTheme.ink)
                    }
                    .font(SettingsTheme.mono(12))
                }
            }

            if startedBackend != .local {
                Button(s.downloadModel) { startLocalDownload() }
                    .buttonStyle(AccentButtonStyle())
                    .frame(maxWidth: .infinity)
            } else {
                switch backendState.status {
                case .loading, .needsSetup:
                    downloadProgress
                case .error:
                    HStack {
                        Text(s.downloadFailed)
                            .font(SettingsTheme.mono(12, .semibold))
                            .foregroundStyle(SettingsTheme.accent)
                        Spacer()
                        Button(s.retry) { startLocalDownload() }
                            .buttonStyle(QuietButtonStyle())
                    }
                case .ready, .processing:
                    Text("✓  \(s.downloaded)")
                        .font(SettingsTheme.mono(12, .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            InkProgressBar(value: backendState.progress)
            HStack {
                // The model still has to be loaded into memory once the files are down.
                Text(backendState.progress >= 1 ? s.preparingModel : s.downloading)
                Spacer()
                Text("\(Int(backendState.progress * 100)) %")
            }
            .font(SettingsTheme.mono(11, .semibold))
            .foregroundStyle(SettingsTheme.ink)
            Text(s.downloadHint)
                .font(SettingsTheme.mono(10))
                .foregroundStyle(SettingsTheme.muted)
        }
    }

    private func startLocalDownload() {
        AppSettings.shared.backend = .local
        startedBackend = .local
        appDelegate.loadBackend()
    }

    // Same normalization as SettingsWindow.save.
    private func saveRemoteSettings() {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") {
            url.removeLast()
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.backend = .remote
        AppSettings.shared.remoteBaseURL = url
        AppSettings.shared.remoteModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.remoteAPIKey = key.isEmpty ? nil : key
        startedBackend = .remote
        appDelegate.loadBackend()
    }

    // MARK: - Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 0) {
            title(s.accessTitle, s.accessSubtitle)
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(accessibilityGranted ? SettingsTheme.ink : SettingsTheme.accent)
                        .frame(width: 8, height: 8)
                    Text(accessibilityGranted ? s.accessGranted : s.accessMissing)
                        .font(SettingsTheme.mono(12, .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink.opacity(0.3), lineWidth: 1))
                .animation(.easeOut(duration: 0.15), value: accessibilityGranted)

                if !accessibilityGranted {
                    Button(s.openSystemSettings) { requestAccessibility() }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    private func requestAccessibility() {
        // Adds Erratly to the Accessibility list (and shows the system prompt
        // the first time); the pane is opened too in case it was denied before.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Practice

    private var tryStep: some View {
        VStack(spacing: 0) {
            title(s.tryTitle, s.trySubtitle)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(s.trySteps(shortcutLabel).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(SettingsTheme.mono(11, .bold))
                            .foregroundStyle(SettingsTheme.accent)
                        Text(line)
                            .font(SettingsTheme.mono(12))
                            .foregroundStyle(SettingsTheme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)

            switch backendState.status {
            case .loading, .needsSetup:
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.waitingForModel)
                        .font(SettingsTheme.mono(11, .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    InkProgressBar(value: backendState.progress)
                }
            case .error:
                Text(s.modelError)
                    .font(SettingsTheme.mono(12, .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .ready, .processing:
                practiceField
            }
        }
    }

    private var practiceField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $sampleText)
                .font(SettingsTheme.mono(14))
                .foregroundStyle(SettingsTheme.ink)
                .tint(SettingsTheme.accent)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(8)
                .frame(height: 96)
                .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(editorFocused ? SettingsTheme.accent : SettingsTheme.ink.opacity(0.3), lineWidth: editorFocused ? 1.5 : 1)
                )
                .onAppear { editorFocused = true }

            HStack {
                if practiceDone {
                    Text("✓  \(s.tryDone)")
                        .font(SettingsTheme.mono(12, .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                }
                Spacer()
                Button(s.correctForMe) { correctForMe() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(backendState.status == .processing)
            }
        }
    }

    /// Runs the real capture → correct → replace pipeline on the whole field,
    /// for users whose shortcut didn't take.
    private func correctForMe() {
        editorFocused = true
        // Let the focus change reach AppKit before reading the first responder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            textView.selectAll(nil)
            appDelegate.previousApp = NSRunningApplication.current
            appDelegate.isShiftTrigger = false
            appDelegate.getSelectedText()
        }
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            title(s.readyTitle, s.readySubtitle)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(s.readyPoints(shortcutLabel), id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("✦").foregroundStyle(SettingsTheme.accent)
                        Text(point)
                            .foregroundStyle(SettingsTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(SettingsTheme.mono(12))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink.opacity(0.3), lineWidth: 1))
            .padding(.bottom, 16)

            Button(s.openSettings) { appDelegate.openSettings() }
                .buttonStyle(QuietButtonStyle())
        }
    }
}

private struct InkProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card)
                RoundedRectangle(cornerRadius: 2)
                    .fill(SettingsTheme.accent)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink.opacity(0.3), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

// MARK: - Copy

/// Onboarding copy, in English and French; every other language falls back to English.
private struct OnboardingStrings {
    let back, next, skip, start: String
    let languageTitle, languageSubtitle, autoDetect: String
    let backendTitle, backendSubtitle, local, remote: String
    let localPoints: [String]
    let downloadModel, downloading, preparingModel, downloadHint, downloaded, downloadFailed, retry, remoteHint: String
    let accessTitle, accessSubtitle, accessGranted, accessMissing, openSystemSettings: String
    let tryTitle, trySubtitle, waitingForModel, modelError, correctForMe, tryDone: String
    let trySteps: (String) -> [String]
    let readyTitle, readySubtitle, openSettings: String
    let readyPoints: (String) -> [String]

    private static func isFrench(_ language: String?) -> Bool {
        if let language { return language == "French" }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }

    static func forLanguage(_ language: String?) -> OnboardingStrings {
        isFrench(language) ? .fr : .en
    }

    static func nativeName(of language: String) -> String {
        [
            "English": "English", "French": "Français", "Spanish": "Español",
            "German": "Deutsch", "Italian": "Italiano", "Portuguese": "Português",
            "Dutch": "Nederlands", "Polish": "Polski", "Russian": "Русский",
            "Japanese": "日本語", "Chinese": "中文", "Korean": "한국어", "Arabic": "العربية"
        ][language] ?? language
    }

    /// A short sentence with deliberate mistakes, in the language being corrected.
    static func sampleSentence(for language: String?) -> String {
        switch language ?? (isFrench(nil) ? "French" : "English") {
        case "French": return "Je pense que se texte contient beaucoup de fote d'ortografe."
        case "Spanish": return "Creo que esta frace tiene muchos herrores de ortografia."
        case "German": return "Ich glaube, dieser Satz hat fiele Feler in der Rechtschreibung."
        case "Italian": return "Penso che questa frasse abbia molti erori di ortografia."
        case "Portuguese": return "Eu axo que esta frase tem muintos erros de ortografia."
        case "Dutch": return "Ik denk dat deze zinn veel speelfouten heefd."
        case "Polish": return "Myśle, że to zdanie ma duzo błendów ortograficznych."
        case "Russian": return "Я думаю, что в этом предложении многа ашибок."
        case "Japanese": return "この分章にはたくさんの間違いがあると思います。"
        case "Chinese": return "我认为这个句子有很多措别字。"
        case "Korean": return "이 문장에는 맞춤법 실수가 만이 있는 것 갔아요."
        case "Arabic": return "اعتقد ان هذه الجملة فيها الكثير من الاخطاء الاملائية."
        default: return "I realy beleive this sentance has to many mistaks in it."
        }
    }

    static let en = OnboardingStrings(
        back: "Back", next: "Continue", skip: "Skip", start: "Start using Erratly",
        languageTitle: "Which language do you write in?",
        languageSubtitle: "Erratly corrects your text in this language. You can change it later from the menu bar.",
        autoDetect: "Auto-detect",
        backendTitle: "Where should corrections run?",
        backendSubtitle: "On your Mac with a local model, or through an OpenAI-compatible API.",
        local: "Local (on-device)", remote: "Remote API",
        localPoints: [
            "Private: your text never leaves your Mac",
            "Works offline once downloaded",
            "One-time download of about 2 GB"
        ],
        downloadModel: "Download model",
        downloading: "Downloading model…",
        preparingModel: "Loading model…",
        downloadHint: "You can continue while it downloads.",
        downloaded: "Model ready",
        downloadFailed: "The download failed.",
        retry: "Retry",
        remoteHint: "Your API key is stored in the macOS Keychain.",
        accessTitle: "Allow Accessibility",
        accessSubtitle: "Erratly needs Accessibility access to read the text you select and replace it with the correction, in any app.",
        accessGranted: "Accessibility access granted",
        accessMissing: "Accessibility access not granted yet",
        openSystemSettings: "Open System Settings",
        tryTitle: "Give it a try",
        trySubtitle: "Erratly fixes spelling and grammar wherever you type, without leaving your app.",
        waitingForModel: "Waiting for the model to finish loading…",
        modelError: "The model couldn't be loaded. Go back to check your settings.",
        correctForMe: "Correct it for me",
        tryDone: "Nice, that's all there is to it!",
        trySteps: { shortcut in [
            "Select the text below",
            "Press \(shortcut)" + (shortcut == "⌃ ⌃" ? " (tap Control twice)" : ""),
            "Review the fixes and accept them"
        ] },
        readyTitle: "You're ready to go",
        readySubtitle: "Erratly runs quietly in the background.",
        openSettings: "Settings…",
        readyPoints: { shortcut in [
            "Erratly lives in your menu bar as ✦",
            "Select text in any app and press \(shortcut) to correct it",
            "Add ⇧ to the shortcut to flip “Review before applying”"
        ] }
    )

    static let fr = OnboardingStrings(
        back: "Retour", next: "Continuer", skip: "Passer", start: "Commencer",
        languageTitle: "Dans quelle langue écrivez-vous ?",
        languageSubtitle: "Erratly corrige vos textes dans cette langue. Vous pourrez la changer depuis la barre des menus.",
        autoDetect: "Détection auto",
        backendTitle: "Où faire les corrections ?",
        backendSubtitle: "Sur votre Mac avec un modèle local, ou via une API compatible OpenAI.",
        local: "Local (sur le Mac)", remote: "API distante",
        localPoints: [
            "Privé : votre texte ne quitte jamais votre Mac",
            "Fonctionne hors ligne une fois téléchargé",
            "Téléchargement unique d'environ 2 Go"
        ],
        downloadModel: "Télécharger le modèle",
        downloading: "Téléchargement du modèle…",
        preparingModel: "Chargement du modèle…",
        downloadHint: "Vous pouvez continuer pendant le téléchargement.",
        downloaded: "Modèle prêt",
        downloadFailed: "Le téléchargement a échoué.",
        retry: "Réessayer",
        remoteHint: "Votre clé d'API est stockée dans le trousseau macOS.",
        accessTitle: "Autoriser l'accessibilité",
        accessSubtitle: "Erratly a besoin de l'accès Accessibilité pour lire le texte sélectionné et le remplacer par sa correction, dans n'importe quelle app.",
        accessGranted: "Accès Accessibilité accordé",
        accessMissing: "Accès Accessibilité pas encore accordé",
        openSystemSettings: "Ouvrir les Réglages Système",
        tryTitle: "Essayez",
        trySubtitle: "Erratly corrige l'orthographe et la grammaire partout où vous écrivez, sans quitter votre app.",
        waitingForModel: "En attente du chargement du modèle…",
        modelError: "Le modèle n'a pas pu être chargé. Revenez en arrière pour vérifier vos réglages.",
        correctForMe: "Corriger pour moi",
        tryDone: "Bravo, c'est aussi simple que ça !",
        trySteps: { shortcut in [
            "Sélectionnez le texte ci-dessous",
            "Appuyez sur \(shortcut)" + (shortcut == "⌃ ⌃" ? " (deux fois sur Contrôle)" : ""),
            "Vérifiez les corrections et acceptez-les"
        ] },
        readyTitle: "Tout est prêt",
        readySubtitle: "Erratly tourne discrètement en arrière-plan.",
        openSettings: "Réglages…",
        readyPoints: { shortcut in [
            "Erratly se trouve dans la barre des menus : ✦",
            "Sélectionnez du texte dans n'importe quelle app et appuyez sur \(shortcut)",
            "Ajoutez ⇧ au raccourci pour inverser « Vérifier avant d'appliquer »"
        ] }
    )
}
