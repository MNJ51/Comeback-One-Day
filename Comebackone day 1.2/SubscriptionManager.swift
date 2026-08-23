//
//  SubscriptionManager.swift
//  Comebackone day 1.2
//
//  StoreKit 2 wrapper for the "Itinerary Plus" auto-renewable subscription that
//  unlocks day-itinerary generation. The product itself has to exist in App
//  Store Connect before this can load/purchase for real — see Configuration.storekit
//  at the project root for local testing without that (Xcode: Product > Scheme >
//  Edit Scheme > Run > Options > StoreKit Configuration).
//

import StoreKit
import Combine

@MainActor
final class SubscriptionManager: ObservableObject {
    static let itineraryPlusProductID = "com.michaeljee.Comebackone-day-1-1.itineraryplus.monthly"

    @Published private(set) var isSubscribed = false
    @Published private(set) var product: Product?
    @Published var purchaseError: String?
    /// True once a load has finished (success or not) — distinguishes "still
    /// loading" from "loaded, but there's genuinely no product" so the paywall
    /// doesn't spin forever when, say, the App Store Connect product doesn't
    /// exist yet or there's no local StoreKit configuration active.
    @Published private(set) var hasAttemptedLoad = false

    private var updateListenerTask: Task<Void, Never>?

    init() {
        updateListenerTask = listenForTransactionUpdates()
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.itineraryPlusProductID])
            product = products.first
        } catch {
            purchaseError = "Couldn't load subscription info: \(error.localizedDescription)"
        }
        hasAttemptedLoad = true
    }

    func purchase() async {
        guard let product else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                case .unverified(let transaction, let verificationError):
                    // StoreKit couldn't verify the transaction's signature. Still
                    // finish it and refresh so local/sandbox testing isn't stuck
                    // silently on the paywall, but surface the error — this
                    // shouldn't happen with a real App Store purchase.
                    purchaseError = "Purchase completed but couldn't be verified: \(verificationError.localizedDescription)"
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlement() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.itineraryPlusProductID {
                subscribed = true
            }
        }
        isSubscribed = subscribed
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
