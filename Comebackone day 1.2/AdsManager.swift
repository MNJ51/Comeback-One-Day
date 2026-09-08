//
//  AdsManager.swift
//  Comebackone day 1.2
//
//  Starts the Google Mobile Ads SDK and owns the StoreKit 2 "Remove Ads"
//  non-consumable purchase that turns banner ads off. StoreKit half mirrors
//  SubscriptionManager's pattern — see Configuration.storekit for local
//  testing without an App Store Connect product.
//
//  The bannerAdUnitID/keyword hints below use Google's official test values.
//  AdMob has no per-app "only show category X" setting — the keywords just
//  nudge its contextual targeting toward travel/food/hospitality ads; swap
//  bannerAdUnitID for a real AdMob ad unit ID (and the GADApplicationIdentifier
//  in Info.plist for your real AdMob App ID) before shipping.
//

import StoreKit
import GoogleMobileAds
import Combine

@MainActor
final class AdsManager: ObservableObject {
    static let removeAdsProductID = "com.michaeljee.Comebackone-day-1-1.removeads"
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
    static let bannerHeight: CGFloat = 50
    static let contextualKeywords = ["travel", "restaurants", "hotels", "vacation", "food", "sightseeing", "tourism"]

    @Published private(set) var isAdRemoved = false
    @Published private(set) var product: Product?
    @Published var purchaseError: String?
    /// True once a load has finished (success or not) — distinguishes "still
    /// loading" from "loaded, but there's genuinely no product" so Settings
    /// doesn't spin forever when the App Store Connect product doesn't exist
    /// yet or there's no local StoreKit configuration active.
    @Published private(set) var hasAttemptedLoad = false

    private var updateListenerTask: Task<Void, Never>?

    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        GADMobileAds.sharedInstance().requestConfiguration.maxAdContentRating = GADMaxAdContentRating.general

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
            let products = try await Product.products(for: [Self.removeAdsProductID])
            product = products.first
        } catch {
            purchaseError = "Couldn't load Remove Ads info: \(error.localizedDescription)"
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
                    if transaction.productID == Self.removeAdsProductID {
                        isAdRemoved = true
                    }
                case .unverified(let transaction, let verificationError):
                    purchaseError = "Purchase completed but couldn't be verified: \(verificationError.localizedDescription)"
                    await transaction.finish()
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
        await refreshEntitlement()
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
        var removed = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.removeAdsProductID {
                removed = true
            }
        }
        isAdRemoved = removed
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
