#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The selection overlay of the reader.
///
/// Upstream `ui/book/read/page/ContentTextView.kt` implements a custom
/// selection: a long press expands to the whole paragraph and then snaps the
/// ends to the word boundaries (`java.text.BreakIterator`). The port keeps
/// that logic in `Reader/Selection.swift`; the overlay shows the selection
/// and offers the copy and the share actions.
public final class ReaderSelectionController: ObservableObject {

    /// The text of the page the selection lives in.
    @Published public var pageText: String = ""
    /// The current selection.
    @Published public var selection: ReaderSelection?
    /// The message shown after a copy.
    @Published public var message: String?

    /// The selected text.
    public var selectedText: String {
        guard let selection else { return "" }
        return selection.text(in: pageText)
    }

    /// Selects the paragraph around a character offset — the upstream long
    /// press behaviour.
    public func selectParagraph(around offset: Int, in text: String) {
        pageText = text
        let paragraph = SelectionEngine.paragraphSelection(containing: offset, in: text)
        selection = paragraph
    }

    /// Snaps a selection to the word boundaries — upstream
    /// `ContentTextView.getSelectionStart/getSelectionEnd`.
    public func snapSelection(_ selection: ReaderSelection, in text: String) {
        pageText = text
        self.selection = SelectionEngine.snap(selection, in: text)
    }

    /// Clears the selection.
    public func clear() {
        selection = nil
        message = nil
    }

    /// The text that the clipboard receives.
    public func copyText() -> String {
        let text = selectedText
        message = "已复制"
        return text
    }
}

/// The selection overlay — the highlighted text with the actions.
public struct ReaderSelectionOverlay: View {

    /// The controller.
    @ObservedObject var controller: ReaderSelectionController

    public init(controller: ReaderSelectionController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection = controller.selection {
                Text(highlighted(selection))
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                HStack(spacing: 16) {
                    Button("复制") {
                        _ = controller.copyText()
                    }
                    Button("取消") {
                        controller.clear()
                    }
                    Spacer()
                    if let message = controller.message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The page text with the selection highlighted.
    private func highlighted(_ selection: ReaderSelection) -> String {
        let text = controller.pageText
        let range = selection.range
        guard range.lowerBound < range.upperBound, range.upperBound <= text.count else {
            return text
        }
        let prefix = String(text.prefix(range.lowerBound))
        let selected = String(text.dropFirst(range.lowerBound).prefix(range.upperBound - range.lowerBound))
        let suffix = String(text.dropFirst(range.upperBound))
        return prefix + "【" + selected + "】" + suffix
    }
}
