#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The result of a dictionary lookup — upstream `DictDialog`.
public struct DictLookupResult: Identifiable, Equatable, Sendable {

    public let id: Int
    /// The word that was looked up.
    public let word: String
    /// The answer of the rule.
    public let result: String
    /// The name of the rule that answered.
    public let ruleName: String

    public init(id: Int = 0, word: String, result: String, ruleName: String) {
        self.id = id
        self.word = word
        self.result = result
        self.ruleName = ruleName
    }
}

/// The dictionary lookup of the reader — upstream `ui/book/read/dialog/DictDialog.kt`.
///
/// The upstream shows the result of `DictRule.search(word)` in a dialog with
/// the rule name; the port shows the same text plus the rule that answered.
public struct DictDialogView: View {

    /// The word that was looked up.
    public let word: String
    /// The answer of the rule.
    public let result: String
    /// The name of the rule that answered.
    public let ruleName: String

    @Environment(\.dismiss) private var dismiss

    public init(word: String, result: String, ruleName: String) {
        self.word = word
        self.result = result
        self.ruleName = ruleName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(word)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
            Text("词典规则: \(ruleName)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            ScrollView {
                Text(result)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}
