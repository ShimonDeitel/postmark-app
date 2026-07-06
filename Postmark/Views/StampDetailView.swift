import SwiftUI
import SwiftData

/// One stamp: mounted photo, catalog rows, used/mint values, the expertize
/// flag, then album page and notes.
struct StampDetailView: View {
    @Bindable var item: StampItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case page, notes
    }

    @FocusState private var focusedField: Field?
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            BaizeBackdrop(intensity: 0.4)

            ScrollView {
                VStack(spacing: 16) {
                    hero
                    catalogCard
                    valueCard
                    organizeCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Real tap-outside keyboard dismiss (house rule).
        .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
        .confirmationDialog(
            "Remove this stamp from the album?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Group {
                if let data = item.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        PostmarkTheme.creamDeep
                        Image(systemName: "seal")
                            .font(.system(size: 52))
                            .foregroundStyle(PostmarkTheme.inkSoft.opacity(0.5))
                    }
                }
            }
            .frame(width: 214, height: 214)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(11)
            .stampMount()
            .shadow(color: PostmarkTheme.baizeDeep.opacity(0.8), radius: 16, y: 9)

            Text(item.displayName)
                .font(PostmarkTheme.heading(20, weight: .bold))
                .foregroundStyle(PostmarkTheme.cream)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Catalog card

    private var catalogCard: some View {
        card {
            catalogRow("COUNTRY", item.country)
            catalogRow("ISSUE", item.issue)
            catalogRow("YEAR", item.year > 0 ? String(item.year) : "")
            catalogRow("DENOM", item.denomination)
            catalogRow("VARIETY", item.variety)
            catalogRow("CONF", "\(Int(item.confidence * 100))%")
        }
    }

    private func catalogRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(PostmarkTheme.catalog(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(PostmarkTheme.red.opacity(0.8))
                .frame(width: 74, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(PostmarkTheme.catalog(13))
                .foregroundStyle(value.isEmpty ? PostmarkTheme.inkSoft : PostmarkTheme.ink)
            Spacer(minLength: 0)
        }
    }

    // MARK: Value card

    private var valueCard: some View {
        card {
            HStack(spacing: 0) {
                valueColumn("USED", low: item.valueLowUsed, high: item.valueHighUsed)
                Rectangle()
                    .fill(PostmarkTheme.inkSoft.opacity(0.3))
                    .frame(width: 1)
                valueColumn("MINT", low: item.valueLowMint, high: item.valueHighMint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(PostmarkTheme.inkSoft.opacity(0.35), lineWidth: 1)
            )

            Text("An estimate, not an appraisal.")
                .font(PostmarkTheme.text(11).italic())
                .foregroundStyle(PostmarkTheme.inkSoft)

            if let url = item.ebaySoldListingsURL {
                Link(destination: url) {
                    HStack {
                        Text("See real sold prices")
                            .font(PostmarkTheme.text(15, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(PostmarkTheme.cream)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(PostmarkTheme.red))
                }
            }

            Toggle(isOn: $item.worthExpertizing) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PostmarkTheme.red)
                    Text("Worth expertizing")
                        .font(PostmarkTheme.text(15))
                        .foregroundStyle(PostmarkTheme.ink)
                }
            }
            .tint(PostmarkTheme.red)
        }
    }

    private func valueColumn(_ label: String, low: Double, high: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(PostmarkTheme.catalog(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(PostmarkTheme.inkSoft)
            Text(rangeText(low: low, high: high))
                .font(PostmarkTheme.heading(18, weight: .bold))
                .foregroundStyle(PostmarkTheme.red)
        }
        .frame(maxWidth: .infinity)
    }

    private func rangeText(low: Double, high: Double) -> String {
        guard high > 0 else { return "—" }
        let l = low.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        let h = high.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return "\(l)-\(h)"
    }

    // MARK: Organize

    private var organizeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALBUM PAGE")
                    .font(PostmarkTheme.catalog(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(PostmarkTheme.red.opacity(0.8))
                TextField("e.g. USA 1900-1950", text: $item.albumPage)
                    .font(PostmarkTheme.text(15))
                    .foregroundStyle(PostmarkTheme.ink)
                    .focused($focusedField, equals: .page)
                    .padding(10)
                    .background(fieldBackground)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES")
                    .font(PostmarkTheme.catalog(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(PostmarkTheme.red.opacity(0.8))
                TextField("Provenance, condition, hunches…", text: $item.notes, axis: .vertical)
                    .font(PostmarkTheme.text(15))
                    .foregroundStyle(PostmarkTheme.ink)
                    .lineLimit(3...8)
                    .focused($focusedField, equals: .notes)
                    .padding(10)
                    .background(fieldBackground)
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PostmarkTheme.creamDeep.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(PostmarkTheme.inkSoft.opacity(0.25), lineWidth: 1)
            )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 14) {
            Text("Mounted \(item.createdAt.formatted(date: .long, time: .omitted))")
                .font(PostmarkTheme.catalog(11))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.45))
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("Remove from the album")
                    .font(PostmarkTheme.text(14, weight: .medium))
                    .foregroundStyle(PostmarkTheme.red.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: Card chrome

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .stampMount()
        .shadow(color: PostmarkTheme.baizeDeep.opacity(0.6), radius: 10, y: 6)
    }
}
