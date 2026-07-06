import SwiftUI
import SwiftData

@main
struct PostmarkApp: App {
    @State private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(for: StampItem.self)
    }
}

/// Single-stack navigation: Scan is home; the album is a link in its corner.
/// No tab bar — two destinations don't earn one. (Attic convention.)
// PLACEHOLDER UI — plain shell, no visual design yet.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ScanView()
        }
    }
}
