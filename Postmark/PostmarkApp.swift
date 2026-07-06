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
/// No tab bar — two destinations don't earn one.
struct RootView: View {
    var body: some View {
        Group {
            #if DEBUG
            if let screen = ProcessInfo.processInfo.environment["POSTMARK_SCREEN"] {
                DebugScreenHost(screen: screen)
            } else {
                mainNavigation
            }
            #else
            mainNavigation
            #endif
        }
        .tint(PostmarkTheme.gilt)
        .preferredColorScheme(.dark)
    }

    private var mainNavigation: some View {
        NavigationStack {
            ScanView()
        }
    }
}

#if DEBUG
/// Dev-only direct screen routing for headless screenshot verification:
/// SIMCTL_CHILD_POSTMARK_SCREEN=album|paywall|reveal xcrun simctl launch …
/// Never compiled into Release.
private struct DebugScreenHost: View {
    let screen: String
    @Environment(\.modelContext) private var context

    var body: some View {
        switch screen {
        case "paywall":
            PaywallView()
        case "album":
            NavigationStack { AlbumView() }
                .tint(PostmarkTheme.gilt)
                .task { seedSamplesIfEmpty() }
        case "reveal":
            ZStack {
                BaizeBackdrop()
                PostmarkTheme.baizeDeep.opacity(0.78).ignoresSafeArea()
                StampRevealView(
                    result: .debugSample, photo: nil, onAlbum: {}, onNext: {}
                )
                .padding(.horizontal, 22)
            }
        default:
            NavigationStack { ScanView() }
        }
    }

    private func seedSamplesIfEmpty() {
        let count = (try? context.fetchCount(FetchDescriptor<StampItem>())) ?? 0
        guard count == 0 else { return }
        let samples: [StampItem] = [
            StampItem(
                country: "Great Britain", issue: "Penny Black", year: 1840,
                denomination: "1d", variety: "Plate 5, red cancel",
                valueLowUsed: 180, valueHighUsed: 420, valueLowMint: 3000, valueHighMint: 9000,
                confidence: 0.71, searchTerm: "penny black 1840 used", albumPage: "GB Classics",
                worthExpertizing: true
            ),
            StampItem(
                country: "USA", issue: "Columbian Exposition", year: 1893,
                denomination: "2c", variety: "Broken hat variety",
                valueLowUsed: 1, valueHighUsed: 5, valueLowMint: 18, valueHighMint: 45,
                confidence: 0.85, searchTerm: "1893 columbian 2 cent broken hat",
                albumPage: "USA 1890s"
            ),
            StampItem(
                country: "Japan", issue: "Cherry Blossom series", year: 1961,
                denomination: "10y", variety: "",
                valueLowUsed: 0.5, valueHighUsed: 2, valueLowMint: 3, valueHighMint: 8,
                confidence: 0.78, searchTerm: "japan 1961 cherry blossom 10 yen"
            ),
            StampItem(
                country: "Germany", issue: "Inflation overprint", year: 1923,
                denomination: "2 Mio.", variety: "Shifted overprint",
                valueLowUsed: 4, valueHighUsed: 15, valueLowMint: 10, valueHighMint: 30,
                confidence: 0.62, searchTerm: "germany 1923 inflation overprint 2 millionen",
                albumPage: "Weimar"
            ),
        ]
        for sample in samples {
            context.insert(sample)
        }
    }
}

extension StampResult {
    static let debugSample = StampResult(
        country: "Great Britain",
        issue: "Penny Black",
        year: 1840,
        denomination: "1d",
        variety: "Plate 5, red Maltese cross cancel",
        valueLowUsed: 180,
        valueHighUsed: 420,
        valueLowMint: 3000,
        valueHighMint: 9000,
        confidence: 0.71,
        searchTerm: "penny black 1840 used"
    )
}
#endif
