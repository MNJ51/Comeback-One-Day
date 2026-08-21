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
    }

    func purchase() async {
        guard let product else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
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
