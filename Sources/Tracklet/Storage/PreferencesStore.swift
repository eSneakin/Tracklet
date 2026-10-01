import Foundation

protocol PreferencesStore {
    func load() -> WidgetPreferences
    func save(_ preferences: WidgetPreferences)
}

final class UserDefaultsPreferencesStore: PreferencesStore {
    // ponytail: suite name isolates future App Group migration to one storage boundary.
    private let defaults: UserDefaults
    private let key = "widget-preferences"

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        if defaults.data(forKey: key) == nil, let previous = legacyDefaults?.data(forKey: key),
           (try? JSONDecoder().decode(WidgetPreferences.self, from: previous)) != nil {
            defaults.set(previous, forKey: key)
        }
    }

    func load() -> WidgetPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(WidgetPreferences.self, from: data)
        else { return WidgetPreferences() }
        return preferences
    }

    func save(_ preferences: WidgetPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
