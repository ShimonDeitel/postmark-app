import SwiftUI
import SwiftData

// PLACEHOLDER UI — plain list + totals, no visual design.
/// The album: every saved stamp, newest first, with collection totals.
struct AlbumView: View {
    @Query(sort: \StampItem.createdAt, order: .reverse) private var items: [StampItem]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                LabeledContent("Stamps", value: "\(items.count)")
                LabeledContent("Estimated value (used)", value: totalText)
                LabeledContent("Worth expertizing", value: "\(items.filter(\.worthExpertizing).count)")
            } header: {
                Text("Collection")
            }

            Section {
                if items.isEmpty {
                    Text("No stamps yet. Scan one from the home screen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            StampDetailView(item: item)
                        } label: {
                            row(item)
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("Stamps")
            }
        }
        .navigationTitle("Album")
    }

    private func row(_ item: StampItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
            HStack(spacing: 8) {
                Text("$\(Int(item.valueLowUsed))-$\(Int(item.valueHighUsed)) used")
                if item.worthExpertizing {
                    Text("EXPERTIZE?")
                        .font(.caption2.bold())
                }
                if !item.albumPage.isEmpty {
                    Text(item.albumPage)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var totalText: String {
        let low = items.reduce(0) { $0 + $1.valueLowUsed }
        let high = items.reduce(0) { $0 + $1.valueHighUsed }
        return "$\(Int(low)) to $\(Int(high))"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}
