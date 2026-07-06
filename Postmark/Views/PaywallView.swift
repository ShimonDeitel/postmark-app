import SwiftUI
import StoreKit

/// Postmark Pro. Shown after the moment of value (first result), never on
/// first launch. Transparent pricing, no trial traps (Apple guideline 5.6).
struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String?
    @State private var isPurchasing = false

    // Live legal pages are a submission blocker; links render once these
    // exist (see MILLION_QUEUE.md shared-infrastructure notes).
    private static let privacyURL: URL? = nil
    private static let termsURL: URL? = nil

    var body: some View {
        ZStack {
            BaizeBackdrop(intensity: 0.7)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PostmarkTheme.cream.opacity(0.65))
                            .padding(10)
                            .background(Circle().fill(PostmarkTheme.baizeDeep.opacity(0.7)))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.top, 14)
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 20) {
                        CancellationMark(diameter: 104)
                            .padding(.top, 2)
                        titleBlock
                        if store.isPro {
                            proActive
                        } else {
                            offerBlock
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
            if selectedProductID == nil {
                selectedProductID = store.products.last?.id ?? StoreManager.yearlyProductID
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 7) {
            Text("Postmark Pro")
                .font(PostmarkTheme.heading(30, weight: .bold))
                .foregroundStyle(PostmarkTheme.cream)
            Text("Every stamp in the shoebox, identified.")
                .font(PostmarkTheme.catalog(13))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Offer

    private var offerBlock: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 11) {
                bullet("Unlimited identifications")
                bullet("Used and mint values on every stamp")
                bullet("Expertizing flags on high-value varieties")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.products.isEmpty {
                if store.isLoadingProducts {
                    ProgressView()
                        .tint(PostmarkTheme.gilt)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 10) {
                        Text("The catalog is stuck shut. One second.")
                            .font(PostmarkTheme.catalog(12))
                            .foregroundStyle(PostmarkTheme.cream.opacity(0.6))
                        Button("Try again") {
                            Task { await store.loadProducts() }
                        }
                        .font(PostmarkTheme.text(15, weight: .semibold))
                        .foregroundStyle(PostmarkTheme.gilt)
                    }
                    .padding(.vertical, 14)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(store.products) { product in
                        productCard(product)
                    }
                }
            }

            purchaseButton

            Button("Restore purchases") {
                Task {
                    await store.restorePurchases()
                    if store.isPro { dismiss() }
                }
            }
            .font(PostmarkTheme.text(14))
            .foregroundStyle(PostmarkTheme.cream.opacity(0.55))

            if let message = store.lastErrorMessage {
                Text(message)
                    .font(PostmarkTheme.text(12))
                    .foregroundStyle(PostmarkTheme.red)
                    .multilineTextAlignment(.center)
            }

            footnote
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundStyle(PostmarkTheme.gilt)
            Text(text)
                .font(PostmarkTheme.text(15))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.9))
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.subscription?.subscriptionPeriod.unit == .year

        return Button {
            PostmarkHaptics.tap()
            selectedProductID = product.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isYearly ? "Yearly" : "Monthly")
                        .font(PostmarkTheme.text(17, weight: .semibold))
                        .foregroundStyle(PostmarkTheme.ink)
                    if isYearly, let monthly = yearlyPerMonthText(product) {
                        Text("\(monthly) a month")
                            .font(PostmarkTheme.catalog(11))
                            .foregroundStyle(PostmarkTheme.inkSoft)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(product.displayPrice)
                        .font(PostmarkTheme.heading(19, weight: .bold))
                        .foregroundStyle(PostmarkTheme.ink)
                    Text(isYearly ? "per year" : "per month")
                        .font(PostmarkTheme.catalog(10))
                        .foregroundStyle(PostmarkTheme.inkSoft)
                }
            }
            .padding(16)
            .background(PostmarkTheme.cream)
            .clipShape(PerforatedRect(notchRadius: 3.5, notchSpacing: 13), style: FillStyle(eoFill: true))
            .overlay(
                PerforatedRect(notchRadius: 3.5, notchSpacing: 13)
                    .stroke(
                        isSelected ? PostmarkTheme.red : PostmarkTheme.creamDeep,
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isYearly, let savings = yearlySavingsText {
                    Text(savings)
                        .font(PostmarkTheme.catalog(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(PostmarkTheme.cream)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(PostmarkTheme.red))
                        .offset(x: -8, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Honest math from live StoreKit prices, never hardcoded copy.
    private func yearlyPerMonthText(_ yearly: Product) -> String? {
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle.precision(.fractionLength(2)))
    }

    private var yearlySavingsText: String? {
        guard
            let monthly = store.products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month }),
            let yearly = store.products.first(where: { $0.subscription?.subscriptionPeriod.unit == .year }),
            monthly.price > 0
        else { return nil }
        let fullYear = monthly.price * 12
        guard fullYear > yearly.price else { return nil }
        let fraction = (fullYear - yearly.price) / fullYear
        let percent = Int((NSDecimalNumber(decimal: fraction).doubleValue * 100).rounded())
        return "SAVE \(percent)%"
    }

    private var purchaseButton: some View {
        Button {
            guard let product = store.products.first(where: { $0.id == selectedProductID }) else { return }
            PostmarkHaptics.cancel()
            isPurchasing = true
            Task {
                defer { isPurchasing = false }
                if await store.purchase(product) {
                    PostmarkHaptics.success()
                    dismiss()
                }
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(PostmarkTheme.red)
                    .frame(height: 56)
                    .shadow(color: PostmarkTheme.red.opacity(0.4), radius: 12, y: 5)
                if isPurchasing {
                    ProgressView().tint(PostmarkTheme.cream)
                } else {
                    Text("Open every page")
                        .font(PostmarkTheme.text(18, weight: .bold))
                        .foregroundStyle(PostmarkTheme.cream)
                }
            }
        }
        .disabled(isPurchasing || store.products.isEmpty || selectedProductID == nil)
        .opacity(store.products.isEmpty ? 0.35 : 1)
        .buttonStyle(PressStyle())
    }

    private var footnote: some View {
        VStack(spacing: 8) {
            Text("Auto-renews until cancelled. Cancel anytime in Settings.")
                .font(PostmarkTheme.catalog(10))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.4))
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                if let url = Self.privacyURL {
                    Link("Privacy", destination: url)
                }
                if let url = Self.termsURL {
                    Link("Terms", destination: url)
                }
            }
            .font(PostmarkTheme.catalog(10))
            .foregroundStyle(PostmarkTheme.cream.opacity(0.4))
        }
    }

    // MARK: Pro active

    private var proActive: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(PostmarkTheme.gilt)
            Text("Every page is open.")
                .font(PostmarkTheme.heading(20, weight: .semibold))
                .foregroundStyle(PostmarkTheme.cream)
            Text("Scan the whole shoebox.")
                .font(PostmarkTheme.catalog(12))
                .foregroundStyle(PostmarkTheme.cream.opacity(0.6))
        }
        .padding(.vertical, 28)
    }
}
