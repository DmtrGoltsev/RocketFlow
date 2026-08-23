import Combine
import Foundation

extension AppLanguage {
    static func deviceFallback(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let preferred = preferredLanguages.first else { return .en }
        let languageCode = preferred
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()
        return languageCode == "ru" ? .ru : .en
    }

    var localeIdentifier: String {
        switch self {
        case .ru: "ru_RU"
        case .en: "en_US"
        }
    }
}

struct AppLocalizationCopy: Equatable, Sendable {
    let firebaseUnavailableDiagnostic: String

    init(language: AppLanguage) {
        switch language {
        case .ru:
            firebaseUnavailableDiagnostic =
                "Push-уведомления недоступны: в этой сборке отсутствует конфигурация Firebase."
        case .en:
            firebaseUnavailableDiagnostic =
                "Push notifications are unavailable because Firebase is not configured for this build."
        }
    }
}

protocol AppLanguagePersisting {
    func loadLanguage() -> AppLanguage?
    func saveLanguage(_ language: AppLanguage)
}

struct UserDefaultsAppLanguagePersistence: AppLanguagePersisting {
    static let defaultKey = "rocketflow.app-language.v1"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = UserDefaultsAppLanguagePersistence.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadLanguage() -> AppLanguage? {
        if let data = defaults.data(forKey: key),
           let language = try? JSONDecoder().decode(AppLanguage.self, from: data) {
            return language
        }

        guard
            let rawValue = defaults.string(forKey: key),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return nil
        }

        // Migrate the early raw-value representation to the versioned Codable format.
        saveLanguage(language)
        return language
    }

    func saveLanguage(_ language: AppLanguage) {
        guard let data = try? JSONEncoder().encode(language) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
protocol AppLanguageStateProviding: AnyObject {
    var language: AppLanguage { get }
    var localeIdentifier: String { get }
    var languagePublisher: AnyPublisher<AppLanguage, Never> { get }

    func setLanguage(_ language: AppLanguage)
}

@MainActor
final class AppLanguageStore: ObservableObject, AppLanguageStateProviding {
    static let shared = AppLanguageStore()

    @Published private(set) var language: AppLanguage

    private let persistence: any AppLanguagePersisting

    init(
        persistence: any AppLanguagePersisting = UserDefaultsAppLanguagePersistence(),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.persistence = persistence
        let storedLanguage = persistence.loadLanguage()
        let resolvedLanguage = storedLanguage
            ?? AppLanguage.deviceFallback(preferredLanguages: preferredLanguages)
        language = resolvedLanguage
        if storedLanguage == nil {
            persistence.saveLanguage(resolvedLanguage)
        }
    }

    var localeIdentifier: String { language.localeIdentifier }
    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        $language.eraseToAnyPublisher()
    }

    func setLanguage(_ language: AppLanguage) {
        persistence.saveLanguage(language)
        guard self.language != language else { return }
        self.language = language
    }
}
