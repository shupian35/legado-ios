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
/// The upstream shows a **tab per enabled dictionary rule**; selecting a tab
/// looks the word up with that rule and shows the answer
/// (`ui/dict/DictDialog.kt:41-90`). The port does the same: the tabs are the
/// enabled rules (`dictRuleDao.enabled`), the first tab answers at once.
public struct DictDialogView: View {

    /// The word that was looked up.
    public let word: String
    /// The rules — the enabled ones get a tab.
    public let rules: [DictRule]
    /// The network dependencies of the lookup.
    public let dependencies: AnalyzeUrlDependencies

    @State private var selected: String = ""
    @State private var result: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    public init(
        word: String,
        rules: [DictRule],
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) {
        self.word = word
        self.rules = DictRuleManager.enabled(rules)
        self.dependencies = dependencies
    }

    /// The convenience form — the answer is already known.
    public init(word: String, result: String, ruleName: String) {
        self.word = word
        self.rules = [DictRule(name: ruleName, urlRule: "", showRule: "")]
        self.dependencies = AnalyzeUrlDependencies()
        _selected = State(initialValue: ruleName)
        _result = State(initialValue: result)
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
            if rules.count > 1 {
                // Upstream `DictDialog.setupTabLayoutMode` — the tabs are
                // scrollable when there are more than four of them; the port
                // always uses a scrollable picker.
                Picker("词典", selection: $selected) {
                    ForEach(rules) { rule in
                        Text(rule.name).tag(rule.name)
                    }
                }
                .pickerStyle(.segmented)
            }
            if isLoading {
                Text("查询中…")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            ScrollView {
                Text(result)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .task {
            await select(ruleNamed: rules.first?.name)
        }
        .onChange(of: selected) { _, value in
            Task { await select(ruleNamed: value) }
        }
    }

    /// Looks the word up with the rule — upstream
    /// `DictViewModel.dict(dictRule, word)`.
    private func select(ruleNamed name: String?) async {
        guard let name, let rule = rules.first(where: { $0.name == name }) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await DictSearcher.search(
                rule: rule,
                word: word,
                dependencies: dependencies
            )
            result = text
            errorMessage = nil
        } catch {
            result = ""
            errorMessage = error.localizedDescription
        }
    }
}
