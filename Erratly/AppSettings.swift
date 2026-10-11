import Foundation

enum Backend: String {
    case local
    case remote
}

enum ReviewPanelSize: String, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var windowSize: NSSize {
        switch self {
        case .small: return NSSize(width: 480, height: 220)
        case .medium: return NSSize(width: 620, height: 320)
        case .large: return NSSize(width: 780, height: 460)
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 15
        }
    }
}

nonisolated final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()
    private init() {}

    private let apiKeyAccount = "erratly-remote-api-key"

    var backend: Backend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "backend"),
                  let value = Backend(rawValue: raw) else { return .local }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "backend") }
    }

    var remoteBaseURL: String {
        get { UserDefaults.standard.string(forKey: "remoteBaseURL") ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteBaseURL") }
    }

    var remoteModelName: String {
        get { UserDefaults.standard.string(forKey: "remoteModelName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteModelName") }
    }

    var reviewPanelSize: ReviewPanelSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "reviewPanelSize"),
                  let value = ReviewPanelSize(rawValue: raw) else { return .small }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "reviewPanelSize") }
    }

    /// nil means the default double Control tap.
    var shortcut: KeyShortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "shortcut") else { return nil }
            return try? JSONDecoder().decode(KeyShortcut.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: "shortcut")
            } else {
                UserDefaults.standard.removeObject(forKey: "shortcut")
            }
        }
    }

    var remoteAPIKey: String? {
        get { KeychainHelper.get(forAccount: apiKeyAccount) }
        set {
            if let key = newValue, !key.isEmpty {
                KeychainHelper.set(key, forAccount: apiKeyAccount)
            } else {
                KeychainHelper.delete(forAccount: apiKeyAccount)
            }
        }
    }
}
