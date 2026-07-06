import SwiftUI
import StoreKit

// PLACEHOLDER UI — functional product list, no visual design.
/// Postmark Pro paywall: unlimited identifications, variety detection,
/// album export. Functional against Postmark.storekit in the simulator.
struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Unlimited identifications")
                    Text("Variety detection")
                    Text("Album export")
                } header: {
                    Text("Postmark Pro")
                } footer: {
                    Text("Free tier: \(StoreManager.freeScanLimit) lifetime identifications, full album browsing.")
                }

                Section("Plans") {
                    if store.isLoadingProducts {
                        ProgressView()
                    } else if store.products.isEmpty {
                        Text("Products unavailable. Try again later.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                purchase(product)
                            } label: {
                                LabeledContent(product.displayName, value: product.displayPrice)
                            }
                            .disabled(purchasing || store.isPro)
                        }
                    }
                }

                Section {
                    if store.isPro {
                        Text("You have Postmark Pro.")
                    }
                    Button("Restore purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .disabled(purchasing)
                    if let message = store.lastErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func purchase(_ product: Product) {
        purchasing = true
        Task {
            let success = await store.purchase(product)
            purchasing = false
            if success { dismiss() }
        }
    }
}
