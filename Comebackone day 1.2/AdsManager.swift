//
//  AdsManager.swift
//  Comebackone day 1.2
//
//  Starts the Meta Audience Network SDK and owns the StoreKit 2 "Remove Ads"
//  non-consumable purchase that turns banner ads off. StoreKit half mirrors
//  SubscriptionManager's pattern — see Configuration.storekit for local
//  testing without an App Store Connect product.
//
//  bannerPlacementID below is a placeholder — swap for a real Meta Audience
//  Network placement ID (created on Meta's Audience Network dashboard) before
//  shipping. No code change needed to test locally: the SDK automatically
//  serves test ads to any app running on the Simulator, regardless of
//  placement ID; testing on a real device needs
//  `FBAdSettings.addTestDevice(FBAdSettings.testDeviceHash)` added once,
//  logged from the console on first run.
//
//  Meta Audience Network has been bidding-only since 2024 — FBAdView's
//  loadAd() is deprecated in favor of loadAdWithBidPayload:, which needs a
//  bid payload from your own server-side bidding integration (typically via
//  a mediation partner). This still uses the deprecated loadAd() since no
//  bidding infrastructure exists here; that's a real follow-up before this
//  can serve genuine (non-test) ads in production, not something this swap
//  solves.
//

import StoreKit
import FBAudienceNetwork
import Combine

@MainActor
final class AdsManager: ObservableObject {
    static let removeAdsProductID = "com.michaeljee.Comebackone-day-1-1.removeads"
    static let bannerPlacementID = "YOUR_PLACEMENT_ID"
    static let bannerHeight: CGFloat = 50
    // Meta Audience Network has no request-level keyword/contextual-targeting
    // API the way AdMob's GADRequest.keywords did — dropped, not replaced.

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
        FBAudienceNetworkAds.initialize(with: nil, completionHandler: nil)

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
