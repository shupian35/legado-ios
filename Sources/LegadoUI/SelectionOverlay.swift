#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The actions of the text selection menu — upstream
/// `res/menu/content_select_action.xml`.
///
/// The upstream shows the first five actions and puts the rest behind the
/// "更多" button (`TextActionMenu.kt:66-67`); the `expandTextMenu` preference
/// shows all of them at once.
public enum TextAction: String, CaseIterable, Identifiable, Sendable {
    case replace = "替换"
    case copy = "复制"
    case bookmark = "书签"
    case readAloud = "朗读"
    case dictionary = "词典"
    case searchContent = "搜索正文"
    case browser = "浏览器"
    case share = "分享"

    public var id: String { rawValue }

    /// The five actions the upstream shows first.
    public static var primary: [TextAction] {
        [.replace, .copy, .bookmark, .readAloud, .dictionary]
    }

    /// The actions behind the "更多" button.
    public static var secondary: [TextAction] {
        [.searchContent, .browser, .share]
    }
}

/// The selection overlay of the reader.
///
/// Upstream `ui/book/read/page/ContentTextView.kt` implements a custom
/// selection: a long press expands to the whole paragraph and then snaps the
/// ends to the word boundaries (`java.text.BreakIterator`). The port keeps
/// that logic in `Reader/Selection.swift`; the overlay shows the selection
/// and offers the upstream actions (`TextActionMenu.kt`).
public final class ReaderSelectionController: ObservableObject {

    /// The text of the page the selection lives in.
    @Published public var pageText: String = ""
    /// The current selection.
    @Published public var selection: ReaderSelection?
    /// The message shown after a copy.
    @Published public var message: String?
    /// Whether the "更多" list is expanded — upstream `expandTextMenu`.
    @Published public var isExpanded = false

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
        isExpanded = false
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

    /// The 替换 action — upstream `ReplaceEditActivity.startIntent(pattern, scope)`.
    var onReplace: (String) -> Void = { _ in }
    /// The 书签 action — upstream `ReadBookActivity.createBookmark`.
    var onBookmark: (String) -> Void = { _ in }
    /// The 朗读 action — upstream `aloudStartSelect` / `speak`.
    var onReadAloud: (String) -> Void = { _ in }
    /// The 词典 action — upstream `DictDialog`.
    var onDictionary: (String) -> Void = { _ in }
    /// The 搜索正文 action — upstream `openSearchActivity`.
    var onSearchContent: (String) -> Void = { _ in }
    /// The 浏览器 action — upstream `menu_browser`.
    var onBrowser: (String) -> Void = { _ in }
    /// The 分享 action — upstream `menu_share_str`.
    var onShare: (String) -> Void = { _ in }
    /// Whether all the actions are shown at once — upstream `expandTextMenu`.
    var isExpanded: Bool = false

    public init(
        controller: ReaderSelectionController,
        onReplace: @escaping (String) -> Void = { _ in },
        onBookmark: @escaping (String) -> Void = { _ in },
        onReadAloud: @escaping (String) -> Void = { _ in },
        onDictionary: @escaping (String) -> Void = { _ in },
        onSearchContent: @escaping (String) -> Void = { _ in },
        onBrowser: @escaping (String) -> Void = { _ in },
        onShare: @escaping (String) -> Void = { _ in },
        isExpanded: Bool = false
    ) {
        self.controller = controller
        self.onReplace = onReplace
        self.onBookmark = onBookmark
        self.onReadAloud = onReadAloud
        self.onDictionary = onDictionary
        self.onSearchContent = onSearchContent
        self.onBrowser = onBrowser
        self.onShare = onShare
        self.isExpanded = isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection = controller.selection {
                Text(highlighted(selection))
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                actions
                if let message = controller.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The action buttons.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ForEach(visibleActions, id: \.id) { action in
                    Button(action.rawValue) {
                        perform(action)
                    }
                    .font(.system(size: 13))
                }
                Spacer()
            }
            if !isExpanded && !TextAction.secondary.isEmpty {
                Button(controller.isExpanded ? "收起" : "更多") {
                    controller.isExpanded.toggle()
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
    }

    /// The actions that are visible — the upstream shows the first five and
    /// the rest behind the "更多" button.
    private var visibleActions: [TextAction] {
        if isExpanded || controller.isExpanded {
            return TextAction.allCases
        }
        return TextAction.primary
    }

    /// Runs the action and dismisses the menu — upstream `onMenuActionFinally`.
    private func perform(_ action: TextAction) {
        let text = controller.selectedText
        switch action {
        case .copy:
            UIPasteboardShim.copy(controller.copyText())
        case .replace:
            onReplace(text)
        case .bookmark:
            onBookmark(text)
        case .readAloud:
            onReadAloud(text)
        case .dictionary:
            onDictionary(text)
        case .searchContent:
            onSearchContent(text)
        case .browser:
            onBrowser(text)
        case .share:
            onShare(text)
        }
        controller.clear()
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
