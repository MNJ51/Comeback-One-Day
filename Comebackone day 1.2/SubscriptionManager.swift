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
        print("🔍ITIN: loadProduct() called, looking up id=\(Self.itineraryPlusProductID)")
        do {
            let products = try await Product.products(for: [Self.itineraryPlusProductID])
            print("🔍ITIN: loadProduct() got \(products.count) product(s): \(products.map(\.id))")
            product = products.first
        } catch {
            print("🔍ITIN: loadProduct() threw: \(error)")
            purchaseError = "Couldn't load subscription info: \(error.localizedDescription)"
        }
        hasAttemptedLoad = true
    }

    func purchase() async {
        guard let product else {
            print("🔍ITIN: purchase() called but product is nil — bailing out")
            return
        }
        print("🔍ITIN: purchase() called for \(product.id)")
        do {
            let result = try await product.purchase()
            print("🔍ITIN: product.purchase() returned")
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("🔍ITIN: purchase result = success/verified, productID=\(transaction.productID)")
                    await transaction.finish()
                case .unverified(let transaction, let verificationError):
                    print("🔍ITIN: purchase result = success/UNVERIFIED, productID=\(transaction.productID), error=\(verificationError)")
                    purchaseError = "Purchase completed but couldn't be verified: \(verificationError.localizedDescription)"
                    await transaction.finish()
                }
            case .userCancelled:
                print("🔍ITIN: purchase result = userCancelled")
            case .pending:
                print("🔍ITIN: purchase result = pending")
                purchaseError = "Purchase is pending approval."
            @unknown default:
                print("🔍ITIN: purchase result = unknown case")
            }
        } catch {
            print("🔍ITIN: product.purchase() threw: \(error)")
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
        // Always refresh, even on .userCancelled: StoreKit's "you already own
        // this" info sheet (shown when re-tapping Subscribe on an active
        // subscription) resolves as .userCancelled since nothing new was
        // purchased — but the entitlement is real and this is the only place
        // that would otherwise notice it.
        await refreshEntitlement()
        print("🔍ITIN: purchase() finished, isSubscribed=\(isSubscribed)")
    }

    func restorePurchases() async {
        print("🔍ITIN: restorePurchases() called")
        do {
            try await AppStore.sync()
            print("🔍ITIN: AppStore.sync() completed")
            await refreshEntitlement()
        } catch {
            print("🔍ITIN: AppStore.sync() threw: \(error)")
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlement() async {
        var subscribed = false
        var seenAny = false
        for await result in Transaction.currentEntitlements {
            seenAny = true
            switch result {
            case .verified(let transaction):
                print("🔍ITIN: currentEntitlements verified productID=\(transaction.productID)")
                if transaction.productID == Self.itineraryPlusProductID {
                    subscribed = true
                }
            case .unverified(let transaction, let error):
                print("🔍ITIN: currentEntitlements UNVERIFIED productID=\(transaction.productID), error=\(error)")
            }
        }
        if !seenAny {
            print("🔍ITIN: currentEntitlements yielded NOTHING at all")
        }
        print("🔍ITIN: refreshEntitlement() setting isSubscribed=\(subscribed)")
        isSubscribed = subscribed
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                print("🔍ITIN: Transaction.updates fired")
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
