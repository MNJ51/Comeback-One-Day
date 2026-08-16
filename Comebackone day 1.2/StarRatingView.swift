//
//  StarRatingView.swift
//  Comebackone day 1.2
//

import SwiftUI

/// Tappable 1–5 star picker. Tapping the current rating clears it back to 0.
struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
    }
}

/// Read-only star display; renders nothing when unrated.
struct StarRatingLabel: View {
    let rating: Int
    var font: Font = .body

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(font)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }
}
