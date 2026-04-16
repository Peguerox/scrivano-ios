import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇩🇴"
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var language: AppLanguage

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        language = AppLanguage(rawValue: saved) ?? .english
    }

    func set(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: "appLanguage")
    }

    /// Returns the localized string for the given key in the current language.
    /// Falls back to English, then to the key itself if not found.
    func t(_ key: String) -> String {
        AppTranslations.strings[language]?[key]
            ?? AppTranslations.strings[.english]?[key]
            ?? key
    }
}
