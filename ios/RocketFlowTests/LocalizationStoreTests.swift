import Combine
import Foundation
import XCTest
@testable import RocketFlow

final class LocalizationStoreTests: XCTestCase {
    func testAppLanguageCodableRoundTrip() throws {
        for language in AppLanguage.allCases {
            let data = try JSONEncoder().encode(language)
            XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: data), language)
        }
    }

    func testDeviceFallbackRecognizesRussianAndDefaultsOtherLanguagesToEnglish() {
        XCTAssertEqual(AppLanguage.deviceFallback(preferredLanguages: ["ru-RU"]), .ru)
        XCTAssertEqual(AppLanguage.deviceFallback(preferredLanguages: ["ru_RU"]), .ru)
        XCTAssertEqual(AppLanguage.deviceFallback(preferredLanguages: ["en-GB"]), .en)
        XCTAssertEqual(AppLanguage.deviceFallback(preferredLanguages: ["de-DE"]), .en)
        XCTAssertEqual(AppLanguage.deviceFallback(preferredLanguages: []), .en)
    }

    func testFirebaseUnavailableCopyIsLocalizedAndUserFacing() {
        let russian = AppLocalizationCopy(language: .ru).firebaseUnavailableDiagnostic
        let english = AppLocalizationCopy(language: .en).firebaseUnavailableDiagnostic

        XCTAssertNotEqual(russian, english)
        XCTAssertTrue(russian.contains("Firebase"))
        XCTAssertTrue(english.contains("Firebase"))
        XCTAssertFalse(russian.contains("GoogleService-Info.plist"))
        XCTAssertFalse(english.contains("GoogleService-Info.plist"))
    }

    @MainActor
    func testMissingFirebaseDiagnosticFollowsCurrentAppLanguageStore() {
        let store = AppLanguageStore(
            persistence: LanguagePersistenceSpy(),
            preferredLanguages: ["en-US"]
        )
        let technical = AppFirebaseMessagingRuntime.missingConfigurationDiagnostic

        XCTAssertEqual(
            AppFirebaseMessagingRuntime.userFacingDiagnostic(
                technical,
                language: store.language
            ),
            AppLocalizationCopy(language: .en).firebaseUnavailableDiagnostic
        )

        store.setLanguage(.ru)

        XCTAssertEqual(
            AppFirebaseMessagingRuntime.userFacingDiagnostic(
                technical,
                language: store.language
            ),
            AppLocalizationCopy(language: .ru).firebaseUnavailableDiagnostic
        )
        XCTAssertEqual(
            AppFirebaseMessagingRuntime.userFacingDiagnostic(
                "Independent technical diagnostic",
                language: store.language
            ),
            "Independent technical diagnostic"
        )
    }

    @MainActor
    func testLegacyRawRussianAndEnglishPreferencesLoadAndMigrateToCodableData() throws {
        for language in AppLanguage.allCases {
            let suiteName = "LocalizationStoreTests.legacy.\(language.rawValue).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(language.rawValue, forKey: UserDefaultsAppLanguagePersistence.defaultKey)

            let store = AppLanguageStore(
                persistence: UserDefaultsAppLanguagePersistence(defaults: defaults),
                preferredLanguages: [language == .ru ? "en-US" : "ru-RU"]
            )

            XCTAssertEqual(store.language, language)
            let migratedData = try XCTUnwrap(
                defaults.data(forKey: UserDefaultsAppLanguagePersistence.defaultKey)
            )
            XCTAssertEqual(
                try JSONDecoder().decode(AppLanguage.self, from: migratedData),
                language
            )
        }
    }

    @MainActor
    func testStorePersistsBeforeAuthenticationAndRestoresPreference() throws {
        let suiteName = "LocalizationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsAppLanguagePersistence(defaults: defaults)

        let initial = AppLanguageStore(
            persistence: persistence,
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(initial.language, .en)
        initial.setLanguage(.ru)

        let restored = AppLanguageStore(
            persistence: persistence,
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(restored.language, .ru)
        XCTAssertEqual(restored.localeIdentifier, "ru_RU")
    }

    @MainActor
    func testMissingOrCorruptPreferenceUsesAndPersistsDeviceFallback() throws {
        let suiteName = "LocalizationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsAppLanguagePersistence.defaultKey)
        let persistence = UserDefaultsAppLanguagePersistence(defaults: defaults)

        let store = AppLanguageStore(
            persistence: persistence,
            preferredLanguages: ["ru-RU"]
        )
        XCTAssertEqual(store.language, .ru)

        let restored = AppLanguageStore(
            persistence: persistence,
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(restored.language, .ru)
        XCTAssertEqual(restored.localeIdentifier, "ru_RU")
    }

    @MainActor
    func testObservableStoreConformsToIntegrationProtocol() {
        let persistence = LanguagePersistenceSpy()
        let store = AppLanguageStore(
            persistence: persistence,
            preferredLanguages: ["en-US"]
        )
        let provider: any AppLanguageStateProviding = store
        var publishedLanguages: [AppLanguage] = []
        let subscription = provider.languagePublisher.sink {
            publishedLanguages.append($0)
        }

        provider.setLanguage(.ru)

        XCTAssertEqual(provider.language, .ru)
        XCTAssertEqual(provider.localeIdentifier, "ru_RU")
        XCTAssertEqual(persistence.savedLanguages, [.en, .ru])
        XCTAssertEqual(publishedLanguages, [.en, .ru])
        withExtendedLifetime(subscription) {}
    }
}

private final class LanguagePersistenceSpy: AppLanguagePersisting {
    private(set) var savedLanguages: [AppLanguage] = []

    func loadLanguage() -> AppLanguage? { nil }
    func saveLanguage(_ language: AppLanguage) { savedLanguages.append(language) }
}
