//
//  BannerAdView.swift
//  Comebackone day 1.2
//

import SwiftUI
import FBAudienceNetwork

/// Thin UIViewRepresentable around FBAdView. Sized directly off
/// AdsManager.bannerHeight rather than an SDK-provided size constant —
/// kFBAdSizeHeight50Banner's width is flexible/container-driven (unlike
/// AdMob's fixed-size GADAdSizeBanner), and this keeps the AdBanner view
/// reporting a real, stable height immediately rather than depending on the
/// ad finishing its async load first, which is what ContentView's
/// GeometryReader-based bottomReservedHeight measurement needs.
private struct BannerAdView: UIViewRepresentable {
    let placementID: String

    func makeUIView(context: Context) -> FBAdView {
        let rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        let adView = FBAdView(placementID: placementID, adSize: kFBAdSizeHeight50Banner, rootViewController: rootViewController)
        adView.loadAd()
        return adView
    }

    func updateUIView(_ uiView: FBAdView, context: Context) {}
}

/// Drop this in wherever a bottom banner ad should appear — it hides itself
/// once the "Remove Ads" purchase is owned, so callers don't need to check
/// AdsManager.isAdRemoved themselves.
struct AdBanner: View {
    @EnvironmentObject var adsManager: AdsManager

    var body: some View {
        if !adsManager.isAdRemoved {
            BannerAdView(placementID: AdsManager.bannerPlacementID)
                .frame(height: AdsManager.bannerHeight)
                .frame(maxWidth: .infinity)
                .background(.thickMaterial)
        }
    }
}
