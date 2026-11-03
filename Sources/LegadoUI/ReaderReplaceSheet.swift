#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The replace rule of the selected text — upstream
/// `ReplaceEditActivity.startIntent(pattern, scope)`.
///
/// The upstream opens the replace rule editor with the selected text as the
/// pattern and the scope "<book name>;<source url>"; the port creates the
/// rule directly.
public struct ReaderReplaceSheet: View {

    /// The application model.
    @ObservedObject var model: LegadoAppModel
    /// The book the reader shows.
    let book: Book
    /// The pattern — the selected text.
    @Binding var pattern: String
    /// The replacement.
    @Binding var replacement: String

    @Environment(\.dismiss) private var dismiss

    public init(
        model: LegadoAppModel,
        book: Book,
        pattern: Binding<String>,
        replacement: Binding<String>
    ) {
        self.model = model
        self.book = book
        self._pattern = pattern
        self._replacement = replacement
    }

    public var body: some View {
        Form {
            Section("规则") {
                TextField("匹配文本", text: $pattern)
                TextField("替换为", text: $replacement)
                Text("作用范围: \(book.name);\(book.origin)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Section {
                Button("保存") {
                    save()
                }
                Button("取消") {
                    dismiss()
                }
            }
        }
    }

    /// Saves the rule — upstream `ReplaceRuleDao.insert`.
    private func save() {
        let scope = "\(book.name);\(book.origin)"
        var rule = ReplaceRule()
        rule.name = "\(book.name) - \(pattern)"
        rule.pattern = pattern
        rule.replacement = replacement
        rule.scope = scope
        rule.scopeTitle = true
        rule.scopeContent = true
        rule.isEnabled = true
        rule.isRegex = false
        try? model.environment.store.insert(rule)
        dismiss()
    }
}
