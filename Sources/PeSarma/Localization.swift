import AppKit

/// Looks up text in `Resources/<language>.lproj/Localizable.strings`, keyed by
/// the English text itself.
///
/// Without a choice made in the app, macOS picks the language from the user's
/// whole list of preferred languages (Romanian is the fallback). A choice made
/// in the app's Language menu is kept in the app's own preferences and wins.
///
/// The folders are copied into the app by `scripts/build-app.sh`. Running the
/// bare binary, outside the app, shows English.
func L(_ english: String) -> String {
    if let bundle = AppLanguage.bundle {
        return bundle.localizedString(forKey: english, value: english, table: nil)
    }
    return NSLocalizedString(english, comment: "")
}

enum AppLanguage {
    /// Languages the app speaks, each named in its own language.
    static let choices: [(code: String, name: String)] = [
        ("ro", "Română"), ("es", "Español"), ("en", "English"),
    ]

    private static let key = "PeSarmaLanguage"

    /// The code chosen in the app, or nil to follow the system.
    static var chosen: String? {
        get {
            guard let code = UserDefaults.standard.string(forKey: key),
                  choices.contains(where: { $0.code == code }) else { return nil }
            return code
        }
        set {
            if let code = newValue {
                UserDefaults.standard.set(code, forKey: key)
                // Also tells macOS, so system parts (Services, panels) follow
                // after the next launch.
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            cached = nil
        }
    }

    private static var cached: Bundle??

    /// The languages macOS itself prefers, ignoring any override stored for
    /// this app, so going back to "System language" takes effect at once.
    private static var systemPreferences: [String] {
        let value = CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? [String]) ?? Locale.preferredLanguages
    }

    /// The language folder in use: the choice, else the best match for the
    /// system's preferred languages, with Romanian as the fallback.
    static var code: String {
        if let chosen { return chosen }
        let available = choices.map(\.code)
        let match = Bundle.preferredLocalizations(from: available, forPreferences: systemPreferences).first
        return match ?? "ro"
    }

    /// Bundle of the language in use. Nil only when the folder is missing,
    /// as when the bare binary runs outside the app.
    static var bundle: Bundle? {
        if let cached { return cached }
        var found: Bundle?
        if let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            found = Bundle(path: path)
        }
        cached = .some(found)
        return found
    }

    /// The language the app is showing now.
    static var active: String { code }
}
