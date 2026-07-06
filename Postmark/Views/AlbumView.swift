import SwiftUI
import SwiftData

/// The album: a gilt-framed collection total, then stamps mounted on the
/// baize in perforated frames.
struct AlbumView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StampItem.createdAt, order: .reverse) private var items: [StampItem]

    private var totalUsedMid: Double {
        items.reduce(0) { $0 + ($1.valueLowUsed + $1.valueHighUsed) / 2 }
    }

    private var expertizeCount: Int {
        items.filter(\.worthExpertizing).count
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ZStack {
            BaizeBackdrop(intensity: 0.55)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        plaque
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    StampCard(item: item)
                                }
                                .buttonStyle(PressStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(item)
                                    } label: {
                                        Label("Remove from album", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("THE ALBUM")
                    .font(PostmarkTheme.catalog(13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(PostmarkTheme.cream)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: StampItem.self) { item in
            StampDetailView(item: item)
        }
    }

    // MARK: Plaque

    private var plaque: some View {
        VStack(spacing: 6) {
            Text("COLLECTION · USED VALUE")
                .font(PostmarkTheme.catalog(10, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(PostmarkTheme.gilt)
            Text("≈ " + totalUsedMid.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                .font(PostmarkTheme.heading(36, weight: .bold))
                .foregroundStyle(PostmarkTheme.cream)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(PostmarkTheme.catalog(11))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(PostmarkTheme.gilt.opacity(0.7), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(PostmarkTheme.baizeDeep.opacity(0.5))
                )
        )
    }

    private var subtitle: String {
        var s = "\(items.count) \(items.count == 1 ? "stamp" : "stamps")"
        if expertizeCount > 0 {
            s += " · \(expertizeCount) worth expertizing"
        }
        return s
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "seal")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(PostmarkTheme.gilt.opacity(0.8))
                .padding(26)
                .overlay(
                    PerforatedRect(notchRadius: 3.5, notchSpacing: 13)
                        .stroke(PostmarkTheme.gilt.opacity(0.45), lineWidth: 1)
                )
            Text("Blank pages")
                .font(PostmarkTheme.heading(22, weight: .semibold))
                .foregroundStyle(PostmarkTheme.cream)
            Text("Scan your first stamp and\nmount it right here.")
                .font(PostmarkTheme.catalog(12))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Stamp card

private struct StampCard: View {
    let item: StampItem

    var body: some View {
        VStack(spacing: 8) {
            photo
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(spacing: 3) {
                Text(item.displayName)
                    .font(PostmarkTheme.text(13, weight: .semibold))
                    .foregroundStyle(PostmarkTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(usedRange)
                    .font(PostmarkTheme.catalog(11, weight: .semibold))
                    .foregroundStyle(PostmarkTheme.red)
            }
        }
        .padding(10)
        .stampMount()
        .overlay(alignment: .topTrailing) {
            if item.worthExpertizing {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(PostmarkTheme.cream, PostmarkTheme.red)
                    .offset(x: 4, y: -4)
                    .accessibilityLabel("Worth expertizing")
            }
        }
        .shadow(color: PostmarkTheme.baizeDeep.opacity(0.7), radius: 9, y: 6)
    }

    @ViewBuilder
    private var photo: some View {
        if let data = item.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                PostmarkTheme.creamDeep
                Image(systemName: "seal")
                    .font(.system(size: 28))
                    .foregroundStyle(PostmarkTheme.inkSoft.opacity(0.5))
            }
        }
    }

    private var usedRange: String {
        guard item.valueHighUsed > 0 else { return "—" }
        let l = item.valueLowUsed.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        let h = item.valueHighUsed.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return "\(l)-\(h) used"
    }
}
