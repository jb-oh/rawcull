import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System Default", bundle: Localization.bundle)
        case .english: return String(localized: "English", bundle: Localization.bundle)
        case .korean: return String(localized: "한국어", bundle: Localization.bundle)
        }
    }
}

@MainActor
@Observable
final class LanguagePreferenceStore {
    static let storageKey = "AppleLanguages"

    var selection: AppLanguage {
        didSet {
            switch selection {
            case .system:
                defaults.removeObject(forKey: Self.storageKey)
            case .english, .korean:
                defaults.set([selection.rawValue], forKey: Self.storageKey)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        domainName: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    ) {
        self.defaults = defaults
        // The global domain also contains AppleLanguages. Only an app override is a selection.
        let languages = defaults.persistentDomain(forName: domainName)?[Self.storageKey] as? [String]
        let code = languages?.first?.split(separator: "-").first.map(String.init)
        selection = code.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}
