//
//  DrawingCanvasView.swift
//  Comebackone day 1.2
//
//  Freeform sketch canvas for journal entries, wrapping PKCanvasView the
//  same way CameraView wraps UIImagePickerController — a thin
//  UIViewRepresentable wrapper around a stock UIKit component with a
//  `@Binding` for its edited value.
//

import PencilKit
import SwiftUI

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 5)
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first {
            canvasView.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
        }
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        context.coordinator.toolPicker = toolPicker
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: DrawingCanvasView
        var toolPicker: PKToolPicker?

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
