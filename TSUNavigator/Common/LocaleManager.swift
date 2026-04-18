import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case ru
    case en

    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var short: String {
        switch self {
        case .ru: return "RU"
        case .en: return "EN"
        }
    }
}

final class LocaleManager: ObservableObject {
    static let shared = LocaleManager()
    private static let storageKey = "app_language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let lang = AppLanguage(rawValue: raw) {
            self.language = lang
        } else {
            self.language = .ru
        }
    }

    func toggle() {
        language = (language == .ru) ? .en : .ru
    }
}

func tr(_ ru: String, _ en: String) -> String {
    LocaleManager.shared.language == .ru ? ru : en
}

struct SettingsView: View {
    @EnvironmentObject private var locale: LocaleManager

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(S.settings.jazyk)) {
                    Picker(selection: Binding(
                        get: { locale.language },
                        set: { locale.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.title).tag(lang)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text(S.settings.jazyk)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle(S.settings.nastrojki)
        }
    }
}
