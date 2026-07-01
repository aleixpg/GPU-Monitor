import Foundation

@MainActor @Observable
final class DisplaySettings {
    static let shared = DisplaySettings()

    var isCompactMode: Bool {
        didSet { UserDefaults.standard.set(isCompactMode, forKey: "compactMode") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "compactMode") == nil {
            isCompactMode = true
        } else {
            isCompactMode = UserDefaults.standard.bool(forKey: "compactMode")
        }
    }
}
