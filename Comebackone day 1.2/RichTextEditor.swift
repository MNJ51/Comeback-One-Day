//
//  RichTextEditor.swift
//  Comebackone day 1.2
//
//  A plain-text editor whose underlying String is treated as lightweight
//  Markdown (rendered via `journalBodyText(_:)` in JournalView.swift wherever
//  an entry's body is displayed) — wraps UITextView rather than SwiftUI's TextEditor
//  because a "Bold this selection" toolbar button needs a real selected
//  range, which TextEditor doesn't expose. Same UIViewRepresentable shape as
//  CameraView's UIViewControllerRepresentable wrapper elsewhere in the app.
//

import SwiftUI
import UIKit

struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Set by the toolbar to request wrapping the current selection (or, if
    /// nothing is selected, inserting at the cursor) in Markdown syntax.
    @Binding var pendingWrap: RichTextWrap?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if let wrap = pendingWrap {
            context.coordinator.applyWrap(wrap, to: uiView)
            DispatchQueue.main.async { pendingWrap = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func applyWrap(_ wrap: RichTextWrap, to textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            let selected = textView.text(in: range) ?? ""
            let replacement = wrap.apply(to: selected)
            textView.replace(range, withText: replacement)
            parent.text = textView.text
        }
    }
}

/// A Markdown wrap the toolbar can request — bold/italic wrap the selection
/// (or insert an empty pair at the cursor), bullet prefixes the current line.
enum RichTextWrap {
    case bold
    case italic
    case bullet

    func apply(to selection: String) -> String {
        switch self {
        case .bold:
            return "**\(selection)**"
        case .italic:
            return "*\(selection)*"
        case .bullet:
            return selection.isEmpty ? "- " : "- \(selection)"
        }
    }
}
