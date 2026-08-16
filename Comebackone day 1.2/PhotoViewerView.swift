//
//  PhotoViewerView.swift
//  Comebackone day 1.2
//
//  Full-screen photo viewer with pinch-to-zoom, double-tap-to-zoom, and
//  panning, so a place's photos can be shown to someone up close.
//

import SwiftUI

struct PhotoViewerView: View {
    let filenames: [String]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(filenames.enumerated()), id: \.offset) { index, filename in
                    if let image = PhotoStore.image(for: filename) {
                        ZoomableImage(image: image)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: filenames.count > 1 ? .always : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .statusBarHidden()
    }
}

/// An image that supports pinch-to-zoom, double-tap-to-zoom, and panning while zoomed in.
private struct ZoomableImage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var anchorScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(magnifyGesture(in: geo.size))
                .simultaneousGesture(dragGesture(in: geo.size))
                .onTapGesture(count: 2) { toggleZoom() }
        }
        .onDisappear(perform: resetZoom)
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(anchorScale * value.magnification, minScale), maxScale)
                offset = clamped(offset, for: scale, in: size)
            }
            .onEnded { _ in
                anchorScale = scale
                if scale <= minScale {
                    withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                let proposed = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
                offset = clamped(proposed, for: scale, in: size)
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                dragStart = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 2.5
                anchorScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        anchorScale = minScale
        offset = .zero
        dragStart = .zero
    }

    /// Keeps the zoomed image from panning past its own edges.
    private func clamped(_ proposed: CGSize, for scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        guard maxX > 0 || maxY > 0 else { return .zero }
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
