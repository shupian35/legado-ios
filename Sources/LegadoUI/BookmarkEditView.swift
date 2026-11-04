#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The bookmark editor — upstream `ui/book/bookmark/BookmarkDialog.kt`
/// (`res/layout/dialog_bookmark.xml`).
///
/// The chapter name is read-only; the 摘录 (the content) and the 备注 are
/// editable; 确定 saves the bookmark and 删除 (only when an existing bookmark
/// is edited — the upstream's `editPos >= 0`) removes it.
public struct BookmarkEditView: View {

    /// The bookmark that is edited — upstream `arguments.getParcelable("bookmark")`.
    public let bookmark: Bookmark

    /// Whether the delete button is shown — upstream `binding.tvFooterLeft.visible(editPos >= 0)`.
    public let showsDelete: Bool

    /// Called with the edited bookmark when the user taps 确定.
    public var onSave: (Bookmark) -> Void

    /// Called when the user taps 删除.
    public var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var bookText: String
    @State private var content: String

    public init(
        bookmark: Bookmark,
        showsDelete: Bool = false,
        onSave: @escaping (Bookmark) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.bookmark = bookmark
        self.showsDelete = showsDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _bookText = State(initialValue: bookmark.bookText)
        _content = State(initialValue: bookmark.content)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Upstream `tvChapterName`.
                Section("章节") {
                    Text(bookmark.chapterName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                // Upstream `editBookText` (the hint is `R.string.content`).
                Section("摘录") {
                    TextEditor(text: $bookText)
                        .frame(minHeight: 140)
                }
                // Upstream `editContent` (the hint is `R.string.note_content`).
                Section("备注") {
                    TextEditor(text: $content)
                        .frame(minHeight: 90)
                }
                if showsDelete {
                    Section {
                        // Upstream `tvFooterLeft` — the delete.
                        Button("删除", role: .destructive) {
                            onDelete?()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .toolbar {
                // Upstream `tvCancel`.
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                // Upstream `tvOk`.
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        var edited = bookmark
                        edited.bookText = bookText
                        edited.content = content
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
    }
}
