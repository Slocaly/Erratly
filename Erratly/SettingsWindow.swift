import Cocoa
import SwiftUI
import Carbon

final class SettingsWindow: NSWindowController {
    private let onSave: (Bool) -> Void

    private let initialBackend: Backend
    private let initialBaseURL: String
    private let initialModelName: String
    private let initialAPIKey: String?
    private let initialShortcut: KeyShortcut?
    private let initialPanelSize: ReviewPanelSize

    init(onSave: @escaping (Bool) -> Void) {
        self.onSave = onSave
        self.initialBackend = AppSettings.shared.backend
        self.initialBaseURL = AppSettings.shared.remoteBaseURL
        self.initialModelName = AppSettings.shared.remoteModelName
        self.initialAPIKey = AppSettings.shared.remoteAPIKey
        self.initialShortcut = AppSettings.shared.shortcut
        self.initialPanelSize = AppSettings.shared.reviewPanelSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 690),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Erratly Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(SettingsTheme.paper)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let view = SettingsView(
            backend: initialBackend,
            baseURL: initialBaseURL,
            apiKey: initialAPIKey ?? "",
            modelName: initialModelName,
            shortcut: initialShortcut,
            panelSize: initialPanelSize,
            onCancel: { [weak self] in self?.window?.close() },
            onSave: { [weak self] backend, baseURL, apiKey, modelName, shortcut, panelSize in
                self?.save(backend: backend, baseURL: baseURL, apiKey: apiKey, modelName: modelName, shortcut: shortcut, panelSize: panelSize)
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func save(backend newBackend: Backend, baseURL: String, apiKey: String, modelName: String, shortcut: KeyShortcut?, panelSize: ReviewPanelSize) {
        var newBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if newBaseURL.hasSuffix("/") {
            newBaseURL.removeLast()
        }
        let newModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let changed = newBackend != initialBackend
            || (newBackend == .remote && (newBaseURL != initialBaseURL || newModelName != initialModelName || newAPIKey != (initialAPIKey ?? "")))

        AppSettings.shared.backend = newBackend
        AppSettings.shared.remoteBaseURL = newBaseURL
        AppSettings.shared.remoteModelName = newModelName
        AppSettings.shared.remoteAPIKey = newAPIKey.isEmpty ? nil : newAPIKey
        AppSettings.shared.shortcut = shortcut
        AppSettings.shared.reviewPanelSize = panelSize

        window?.close()
        onSave(changed)
    }
}

// Mirrors the paper/ink palette of the review panel (DiffPanel) and the
// landing page, and dmg-resources/make_background.py for the install window.
private enum SettingsTheme {
    static let paper = Color(red: 246 / 255, green: 239 / 255, blue: 216 / 255)
    static let card = Color(red: 251 / 255, green: 246 / 255, blue: 230 / 255)
    static let ink = Color(red: 32 / 255, green: 24 / 255, blue: 15 / 255)
    static let muted = Color(red: 138 / 255, green: 127 / 255, blue: 99 / 255)
    static let accent = Color(red: 179 / 255, green: 57 / 255, blue: 46 / 255)
    static let ruleSpacing: CGFloat = 31

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SettingsTheme.mono(10, .bold))
            .tracking(1)
            .foregroundStyle(SettingsTheme.muted)
    }
}

private struct SettingsView: View {
    @State var backend: Backend
    @State var baseURL: String
    @State var apiKey: String
    @State var modelName: String
    @State var shortcut: KeyShortcut?
    @State var panelSize: ReviewPanelSize

    let onCancel: () -> Void
    let onSave: (Backend, String, String, String, KeyShortcut?, ReviewPanelSize) -> Void

    private var remoteEnabled: Bool { backend == .remote }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                PillSwitch(selection: $backend, options: [(.local, "Local (on-device)"), (.remote, "Remote API")])
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 14) {
                    StyledField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: $baseURL)
                    StyledField(label: "API Key", placeholder: "sk-…", text: $apiKey, secure: true)
                    StyledField(label: "Model Name", placeholder: "gpt-4o-mini", text: $modelName)
                }
                .disabled(!remoteEnabled)
                .opacity(remoteEnabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: remoteEnabled)

                ShortcutRecorder(shortcut: $shortcut)
                    .padding(.top, 22)

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Review panel size")
                    PillSwitch(selection: $panelSize, options: ReviewPanelSize.allCases.map { ($0, $0.title) })
                }
                .padding(.top, 22)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { onSave(backend, baseURL, apiKey, modelName, shortcut, panelSize) }
                        .buttonStyle(AccentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 690)
        .preferredColorScheme(.light)
    }

    // Ruled notebook paper, same as the landing page background.
    private var background: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SettingsTheme.paper))
            var y = SettingsTheme.ruleSpacing
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(SettingsTheme.accent.opacity(0.11)))
                y += SettingsTheme.ruleSpacing
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("AppIconRound")
                .resizable()
                .frame(width: 56, height: 56)
                .shadow(color: SettingsTheme.ink.opacity(0.2), radius: 6, y: 3)
            Text("ERRATLY")
                .font(SettingsTheme.mono(15, .bold))
                .tracking(1.5)
                .foregroundStyle(SettingsTheme.ink)
            Text("Choose where corrections run")
                .font(SettingsTheme.mono(12))
                .foregroundStyle(SettingsTheme.muted)
        }
    }
}

// Ink segmented control, styled after the landing page language switch.
private struct PillSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                option(title, value: value)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 3).fill(SettingsTheme.ink))
    }

    private func option(_ title: String, value: Value) -> some View {
        let selected = selection == value
        return Text(title)
            .font(SettingsTheme.mono(12, .bold))
            .foregroundStyle(selected ? SettingsTheme.ink : SettingsTheme.paper.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SettingsTheme.paper)
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
            }
    }
}

private struct StyledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)

            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(SettingsTheme.mono(13))
            .foregroundStyle(SettingsTheme.ink)
            .tint(SettingsTheme.accent)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(focused ? SettingsTheme.accent : SettingsTheme.ink.opacity(0.3), lineWidth: focused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(SettingsTheme.muted.opacity(0.7))
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Shortcut")

            HStack(spacing: 8) {
                Button(action: { recording ? stopRecording() : startRecording() }) {
                    Text(title)
                        .font(SettingsTheme.mono(13, recording ? .regular : .semibold))
                        .foregroundStyle(recording ? SettingsTheme.accent : SettingsTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(recording ? SettingsTheme.accent : SettingsTheme.ink.opacity(0.3), lineWidth: recording ? 1.5 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: recording)

                if shortcut != nil {
                    Button("Use double ⌃") {
                        stopRecording()
                        shortcut = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }

            Text(recording ? "Press a key combination with ⌘, ⌥ or ⌃ — Esc to cancel" : "Add ⇧ to flip “Review before applying”")
                .font(SettingsTheme.mono(10))
                .foregroundStyle(SettingsTheme.muted)
        }
        .onDisappear { stopRecording() }
    }

    private var title: String {
        if recording { return "Type shortcut…" }
        return shortcut?.displayString ?? "⌃ ⌃  (double tap)"
    }

    private func startRecording() {
        guard !recording else { return }
        recording = true
        // The current hot key would otherwise swallow the keystroke if the user
        // types the same combination again.
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(KeyShortcut.relevantModifiers)
            if Int(event.keyCode) == kVK_Escape && flags.isEmpty {
                stopRecording()
            } else if let recorded = KeyShortcut(event: event) {
                shortcut = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if recording {
            recording = false
            HotkeyManager.shared.resume()
        }
    }
}

// Flat, uppercase typewriter buttons matching the review panel's Accept/Cancel.
private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase)
            .font(SettingsTheme.mono(11, .bold))
            .tracking(0.6)
            .foregroundStyle(SettingsTheme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.ink.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase)
            .font(SettingsTheme.mono(11, .bold))
            .tracking(0.6)
            .foregroundStyle(SettingsTheme.ink.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
