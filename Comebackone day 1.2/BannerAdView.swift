//
//  BannerAdView.swift
//  Comebackone day 1.2
//

import SwiftUI
import GoogleMobileAds

/// Thin UIViewRepresentable around GADBannerView. Requests are tagged with
/// AdsManager.contextualKeywords so AdMob's targeting leans toward travel/food
/// content — see AdsManager.swift for why that's a hint, not a guarantee.
private struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController

        let request = GADRequest()
        request.keywords = AdsManager.contextualKeywords
        banner.load(request)

        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

/// Drop this in wherever a bottom banner ad should appear — it hides itself
/// once the "Remove Ads" purchase is owned, so callers don't need to check
/// AdsManager.isAdRemoved themselves.
struct AdBanner: View {
    @EnvironmentObject var adsManager: AdsManager

    var body: some View {
        if !adsManager.isAdRemoved {
            BannerAdView(adUnitID: AdsManager.bannerAdUnitID)
                .frame(width: GADAdSizeBanner.size.width, height: GADAdSizeBanner.size.height)
                .frame(maxWidth: .infinity)
                .background(.thickMaterial)
        }
    }
}
