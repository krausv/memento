import AppKit
import SwiftUI

enum BulletText {
    static let marker = "•"

    /// Odstraní prázdné odrážky a okrajové mezery; prázdný výsledek je `nil`.
    static func clean(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != marker }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// Víceřádkové pole pro poznámku. Enter na řádku s odrážkou přidá další odrážku,
/// Enter na prázdné odrážce seznam ukončí. Prázdné pole začíná odrážkou.
struct BulletTextEditor: NSViewRepresentable {
    @Binding var text: String
    var autofocus = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text.isEmpty ? "\(BulletText.marker) " : text
        if text.isEmpty {
            DispatchQueue.main.async { self.text = textView.string }
        }
        if autofocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scroll.documentView as! NSTextView
        if textView.string != text, !text.isEmpty { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BulletTextEditor

        init(_ parent: BulletTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let string = textView.string as NSString
            var start = 0, end = 0, contentsEnd = 0
            string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: textView.selectedRange().location, length: 0))
            let lineRange = NSRange(location: start, length: contentsEnd - start)
            let line = string.substring(with: lineRange)
            guard line.hasPrefix(BulletText.marker) else { return false }

            if line.trimmingCharacters(in: .whitespaces) == BulletText.marker {
                textView.insertText("", replacementRange: lineRange)
            } else {
                textView.insertText("\n\(BulletText.marker) ", replacementRange: textView.selectedRange())
            }
            return true
        }
    }
}
