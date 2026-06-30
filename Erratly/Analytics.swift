import TelemetryDeck

enum Analytics {
    static func initialize() {
        TelemetryDeck.initialize(config: .init(appID: "364B0E3C-C89A-4572-AEE0-134CB13ABCA8"))
    }

    static func correctionAccepted(language: String?) {
        TelemetryDeck.signal("correctionAccepted", parameters: ["language": language ?? "auto"])
    }

    static func correctionRejected(language: String?) {
        TelemetryDeck.signal("correctionRejected", parameters: ["language": language ?? "auto"])
    }

    static func correctionApplied(language: String?) {
        TelemetryDeck.signal("correctionApplied", parameters: ["language": language ?? "auto"])
    }

    static func correctionNoChange() {
        TelemetryDeck.signal("correctionNoChange")
    }
}
