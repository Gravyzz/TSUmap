import SwiftUI

@main
struct TSUNavigatorApp: App {
    @State var isLoading: Bool = true
    @StateObject private var locale = LocaleManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locale)
                .id(locale.language.rawValue)
        }
    }
}
