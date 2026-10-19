import Foundation
import Testing
@testable import RawCull

@MainActor
struct LanguagePreferenceStoreTests {
    private func withDefaults(_ test: (UserDefaults, String) throws -> Void) throws {
        let suiteName = "RawCullTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try test(defaults, suiteName)
    }

    @Test func systemDefaultIgnoresInheritedLanguageAndDoesNotWriteAnOverride() throws {
        try withDefaults { defaults, domain in
            defaults.register(defaults: [LanguagePreferenceStore.storageKey: ["ko"]])
            #expect(defaults.stringArray(forKey: LanguagePreferenceStore.storageKey) != nil)
            let store = LanguagePreferenceStore(defaults: defaults, domainName: domain)
            #expect(store.selection == .system)
            #expect(defaults.persistentDomain(forName: domain)?[LanguagePreferenceStore.storageKey] == nil)
        }
    }

    @Test(arguments: [AppLanguage.english, .korean])
    func selectingLanguagePersistsOnlyItsCodeAndReadsItBack(language: AppLanguage) throws {
        try withDefaults { defaults, domain in
            let store = LanguagePreferenceStore(defaults: defaults, domainName: domain)
            store.selection = language
            #expect(defaults.persistentDomain(forName: domain)?[LanguagePreferenceStore.storageKey] as? [String] == [language.rawValue])
            #expect(LanguagePreferenceStore(defaults: defaults, domainName: domain).selection == language)
        }
    }

    @Test func systemDefaultRemovesOverrideAndPreservesOtherSettings() throws {
        try withDefaults { defaults, domain in
            defaults.register(defaults: [LanguagePreferenceStore.storageKey: ["ko"]])
            let inheritedLanguages = defaults.stringArray(forKey: LanguagePreferenceStore.storageKey)
            defaults.set("untouched", forKey: "anotherSetting")
            let store = LanguagePreferenceStore(defaults: defaults, domainName: domain)
            store.selection = .english
            store.selection = .korean
            store.selection = .system
            #expect(defaults.persistentDomain(forName: domain)?[LanguagePreferenceStore.storageKey] == nil)
            #expect(defaults.stringArray(forKey: LanguagePreferenceStore.storageKey) == inheritedLanguages)
            #expect(defaults.string(forKey: "anotherSetting") == "untouched")
            #expect(LanguagePreferenceStore(defaults: defaults, domainName: domain).selection == .system)
        }
    }

    @Test func regionalStoredLanguagesAreRecognized() throws {
        try withDefaults { defaults, domain in
            for (code, expected) in [("ko-KR", AppLanguage.korean), ("en-US", .english)] {
                defaults.set([code, "en"], forKey: LanguagePreferenceStore.storageKey)
                #expect(LanguagePreferenceStore(defaults: defaults, domainName: domain).selection == expected)
            }
        }
    }

    @Test func unsupportedEmptyOrMalformedValuesFallBackToSystem() throws {
        try withDefaults { defaults, domain in
            for value: Any in [["fr"], [String](), "ko", 42] {
                defaults.set(value, forKey: LanguagePreferenceStore.storageKey)
                #expect(LanguagePreferenceStore(defaults: defaults, domainName: domain).selection == .system)
            }
        }
    }
}
