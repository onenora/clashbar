import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .zhHans:
            return "zh_Hans_CN"
        case .en:
            return "en_US_POSIX"
        }
    }
}

enum L10n {
    private static let missingBundleMarker = NSNull()
    private static let bundleCacheKeyPrefix = "clashbar.localization.bundle."
    private static let localeCacheKeyPrefix = "clashbar.localization.locale."

    static func t(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        t(key, language: language, args: args)
    }

    static func t(_ key: String, language: AppLanguage, args: [CVarArg]) -> String {
        let format = localizedString(for: key, language: language)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: locale(for: language), arguments: args)
    }

    private static func localizedString(for key: String, language: AppLanguage) -> String {
        if let value = localizedString(in: bundle(for: language), key: key), value != key {
            return value
        }
        if language != .zhHans,
           let fallbackValue = localizedString(in: bundle(for: .zhHans), key: key),
           fallbackValue != key {
            return fallbackValue
        }
        return key
    }

    private static func localizedString(in bundle: Bundle?, key: String) -> String? {
        bundle?.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        let key = bundleCacheKeyPrefix + language.rawValue
        let threadStorage = Thread.current.threadDictionary

        if let cached = threadStorage[key] as? Bundle {
            return cached
        }
        if threadStorage[key] is NSNull {
            return nil
        }

        let resolved = resolveBundle(for: language)
        if let resolved {
            threadStorage[key] = resolved
        } else {
            threadStorage[key] = missingBundleMarker
        }
        return resolved
    }

    private static func resolveBundle(for language: AppLanguage) -> Bundle? {
        let candidateBundles = AppResourceBundleLocator.candidateBundles()
        let candidateDirectories: [String?] = [nil, "Localization", "Resources/Localization"]
        let languageIDs = [language.rawValue, language.rawValue.lowercased()]

        for sourceBundle in candidateBundles {
            for directory in candidateDirectories {
                for languageID in languageIDs {
                    if let path = sourceBundle.path(forResource: languageID, ofType: "lproj", inDirectory: directory),
                       let bundle = Bundle(path: path) {
                        return bundle
                    }
                }
            }
        }
        return nil
    }

    private static func locale(for language: AppLanguage) -> Locale {
        let key = localeCacheKeyPrefix + language.rawValue
        let threadStorage = Thread.current.threadDictionary
        if let cached = threadStorage[key] as? Locale {
            return cached
        }
        let locale = Locale(identifier: language.localeIdentifier)
        threadStorage[key] = locale
        return locale
    }
}
