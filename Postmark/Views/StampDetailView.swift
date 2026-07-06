import SwiftUI
import SwiftData

// PLACEHOLDER UI — plain form, no visual design.
/// One stamp: photo, identification fields, value ranges, eBay sold link,
/// expertizing flag, album page and notes.
struct StampDetailView: View {
    @Bindable var item: StampItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDelete = false

    var body: some View {
        Form {
            if let data = item.photoData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Identification") {
                TextField("Country", text: $item.country)
                TextField("Issue", text: $item.issue)
                TextField("Year", value: $item.year, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Denomination", text: $item.denomination)
                TextField("Variety", text: $item.variety)
                LabeledContent("Confidence", value: "\(Int(item.confidence * 100))%")
            }

            Section("Value (sold ranges, USD)") {
                LabeledContent("Used", value: "$\(Int(item.valueLowUsed)) to $\(Int(item.valueHighUsed))")
                LabeledContent("Mint", value: "$\(Int(item.valueLowMint)) to $\(Int(item.valueHighMint))")
                Text("An estimate, not an appraisal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = item.ebaySoldListingsURL {
                    Link("See real sold prices on eBay", destination: url)
                }
                Toggle("Worth expertizing", isOn: $item.worthExpertizing)
            }

            Section("Album") {
                TextField("Album page (e.g. USA 1900s)", text: $item.albumPage)
                TextField("Notes", text: $item.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                LabeledContent("Added", value: item.createdAt.formatted(date: .long, time: .omitted))
                Button("Remove from album", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        // Real tap-outside keyboard dismiss (house convention:
        // scrollDismissesKeyboard alone is not sufficient).
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
        )
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
}
