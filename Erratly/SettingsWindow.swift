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

    init(onSave: @escaping (Bool) -> Void) {
        self.onSave = onSave
        self.initialBackend = AppSettings.shared.backend
        self.initialBaseURL = AppSettings.shared.remoteBaseURL
        self.initialModelName = AppSettings.shared.remoteModelName
        self.initialAPIKey = AppSettings.shared.remoteAPIKey
        self.initialShortcut = AppSettings.shared.shortcut

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Erratly Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsTheme.bgBottom)
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
            onCancel: { [weak self] in self?.window?.close() },
            onSave: { [weak self] backend, baseURL, apiKey, modelName, shortcut in
                self?.save(backend: backend, baseURL: baseURL, apiKey: apiKey, modelName: modelName, shortcut: shortcut)
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func save(backend newBackend: Backend, baseURL: String, apiKey: String, modelName: String, shortcut: KeyShortcut?) {
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

        window?.close()
        onSave(changed)
    }
}

// Mirrors the palette in dmg-resources/make_background.py so the settings
// window matches the install window.
private enum SettingsTheme {
    static let bgTop = Color(red: 13 / 255, green: 12 / 255, blue: 18 / 255)
    static let bgBottom = Color(red: 7 / 255, green: 7 / 255, blue: 10 / 255)
    static let accent = Color(red: 198 / 255, green: 178 / 255, blue: 245 / 255)
    static let accentSoft = Color(red: 150 / 255, green: 132 / 255, blue: 200 / 255)
    static let textPrimary = Color(red: 240 / 255, green: 238 / 255, blue: 245 / 255)
    static let textSecondary = Color(red: 150 / 255, green: 148 / 255, blue: 158 / 255)
}

private struct SettingsView: View {
    @State var backend: Backend
    @State var baseURL: String
    @State var apiKey: String
    @State var modelName: String
    @State var shortcut: KeyShortcut?

    let onCancel: () -> Void
    let onSave: (Backend, String, String, String, KeyShortcut?) -> Void

    private var remoteEnabled: Bool { backend == .remote }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                BackendSwitch(selection: $backend)
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

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { onSave(backend, baseURL, apiKey, modelName, shortcut) }
                        .buttonStyle(AccentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 620)
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [SettingsTheme.bgTop, SettingsTheme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [SettingsTheme.accentSoft.opacity(0.28), .clear],
                center: UnitPoint(x: 0.5, y: 0.2),
                startRadius: 0,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("AppIconRound")
                .resizable()
                .frame(width: 56, height: 56)
                .shadow(color: SettingsTheme.accentSoft.opacity(0.5), radius: 16)
            Text("Erratly")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SettingsTheme.textPrimary)
            Text("Choose where corrections run")
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.textSecondary)
        }
    }
}

private struct BackendSwitch: View {
    @Binding var selection: Backend
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            option("Local (on-device)", value: .local)
            option("Remote API", value: .remote)
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func option(_ title: String, value: Backend) -> some View {
        let selected = selection == value
        return Text(title)
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SettingsTheme.bgBottom : SettingsTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule()
                        .fill(SettingsTheme.accent)
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Capsule())
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
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsTheme.textSecondary)

            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme.textPrimary)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? SettingsTheme.accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(SettingsTheme.textSecondary.opacity(0.6))
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shortcut")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsTheme.textSecondary)

            HStack(spacing: 8) {
                Button(action: { recording ? stopRecording() : startRecording() }) {
                    Text(title)
                        .font(.system(size: 13, weight: recording ? .regular : .medium))
                        .foregroundStyle(recording ? SettingsTheme.textSecondary : SettingsTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(recording ? SettingsTheme.accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
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
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.textSecondary.opacity(0.8))
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

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SettingsTheme.bgBottom)
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .background(Capsule().fill(SettingsTheme.accent.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme.textSecondary.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Capsule())
    }
}
