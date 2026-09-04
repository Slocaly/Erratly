import Cocoa

final class SettingsWindow: NSWindowController {
    private let onSave: (Bool) -> Void

    private var localRadio: NSButton!
    private var remoteRadio: NSButton!
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelNameField: NSTextField!

    private let initialBackend: Backend
    private let initialBaseURL: String
    private let initialModelName: String
    private let initialAPIKey: String?

    init(onSave: @escaping (Bool) -> Void) {
        self.onSave = onSave
        self.initialBackend = AppSettings.shared.backend
        self.initialBaseURL = AppSettings.shared.remoteBaseURL
        self.initialModelName = AppSettings.shared.remoteModelName
        self.initialAPIKey = AppSettings.shared.remoteAPIKey

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Erratly Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let padding: CGFloat = 20
        let fieldWidth: CGFloat = 360 - padding * 2
        var y: CGFloat = 260 - padding - 20

        let localRadio = NSButton(radioButtonWithTitle: "Local (on-device)", target: self, action: #selector(backendChanged))
        localRadio.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 20)
        contentView.addSubview(localRadio)
        self.localRadio = localRadio
        y -= 26

        let remoteRadio = NSButton(radioButtonWithTitle: "Remote API", target: self, action: #selector(backendChanged))
        remoteRadio.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 20)
        contentView.addSubview(remoteRadio)
        self.remoteRadio = remoteRadio
        y -= 34

        let baseURLLabel = NSTextField(labelWithString: "Base URL")
        baseURLLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(baseURLLabel)
        y -= 20

        let baseURLField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        baseURLField.placeholderString = "https://api.openai.com/v1"
        contentView.addSubview(baseURLField)
        self.baseURLField = baseURLField
        y -= 32

        let apiKeyLabel = NSTextField(labelWithString: "API Key")
        apiKeyLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(apiKeyLabel)
        y -= 20

        let apiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        contentView.addSubview(apiKeyField)
        self.apiKeyField = apiKeyField
        y -= 32

        let modelNameLabel = NSTextField(labelWithString: "Model Name")
        modelNameLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(modelNameLabel)
        y -= 20

        let modelNameField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        modelNameField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelNameField)
        self.modelNameField = modelNameField

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.frame = NSRect(x: 360 - padding - 160, y: padding, width: 75, height: 24)
        cancelButton.keyEquivalent = "\u{1B}"
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveButton.frame = NSRect(x: 360 - padding - 80, y: padding, width: 80, height: 24)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        localRadio.state = initialBackend == .local ? .on : .off
        remoteRadio.state = initialBackend == .remote ? .on : .off
        baseURLField.stringValue = initialBaseURL
        apiKeyField.stringValue = initialAPIKey ?? ""
        modelNameField.stringValue = initialModelName
        updateFieldsEnabled()
    }

    private func updateFieldsEnabled() {
        let remoteEnabled = remoteRadio.state == .on
        baseURLField.isEnabled = remoteEnabled
        apiKeyField.isEnabled = remoteEnabled
        modelNameField.isEnabled = remoteEnabled
    }

    @objc private func backendChanged() {
        updateFieldsEnabled()
    }

    @objc private func cancelAction() {
        window?.close()
    }

    @objc private func saveAction() {
        let newBackend: Backend = remoteRadio.state == .on ? .remote : .local
        let newBaseURL = baseURLField.stringValue
        let newModelName = modelNameField.stringValue
        let newAPIKey = apiKeyField.stringValue

        let changed = newBackend != initialBackend
            || (newBackend == .remote && (newBaseURL != initialBaseURL || newModelName != initialModelName || newAPIKey != (initialAPIKey ?? "")))

        AppSettings.shared.backend = newBackend
        AppSettings.shared.remoteBaseURL = newBaseURL
        AppSettings.shared.remoteModelName = newModelName
        AppSettings.shared.remoteAPIKey = newAPIKey.isEmpty ? nil : newAPIKey

        window?.close()
        onSave(changed)
    }
}
