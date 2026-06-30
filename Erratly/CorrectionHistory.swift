import Foundation

struct CorrectionPair: Codable {
    let original: String
    let corrected: String
}

final class CorrectionHistory {
    static let shared = CorrectionHistory()
    private let key = "correctionHistory"
    private let maxCount = 20

    private init() {}

    var pairs: [CorrectionPair] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CorrectionPair].self, from: data) else {
            return []
        }
        return decoded
    }

    var isEmpty: Bool { pairs.isEmpty }

    func record(original: String, corrected: String) {
        var current = pairs
        current.removeAll { $0.original == original }
        current.insert(CorrectionPair(original: original, corrected: corrected), at: 0)
        if current.count > maxCount { current = Array(current.prefix(maxCount)) }
        if let encoded = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
