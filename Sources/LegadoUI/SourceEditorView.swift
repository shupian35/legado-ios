//
//  SourceEditorView.swift
//  LegadoUI
//
//  The book source editor — upstream `ui/book/source/edit/`.
//
//  The upstream edits every rule with a structured form. The port edits the
//  raw rule JSON, because that is exactly how the rules are stored
//  (`BookSource.ruleSearch` etc. are JSON strings) and because it keeps every
//  rule field the upstream supports — including the ones the upstream form
//  hides.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The source editor.
public struct SourceEditorView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var source: BookSource
    @State private var message: String = ""
    @State private var isChecking = false
    @State private var isHelpPresented = false
    /// The URL field that is being edited — the upstream inserts the URL
    /// option into the focused field.
    @State private var urlOptionTarget: UrlOptionTarget = .search
    /// The upstream `viewModel.autoComplete` — the rule completion is on.
    @State private var autoComplete = false
    @State private var isDebugPresented = false
    @State private var isVariablesPresented = false
    @State private var isQRPresented = false
    /// The QR scanner — upstream `menu_qr_code_camera`.
    @State private var isQRScannerPresented = false
    /// The result of the QR scan.
    @State private var qrResult: String?
    @State private var isSharePresented = false
    @State private var variableText: String = ""
    /// The source the search is scoped to — upstream `menu_search`.
    @State private var searchSource: BookSource?
    @State private var isSearchPresented = false
    /// The source the editor was opened with — the upstream compares the
    /// edited source with it to ask before the exit.
    @State private var originalSource: BookSource
    /// Whether the exit confirmation is shown — upstream `BookSourceEditActivity.finish`.
    @State private var isExitConfirmed = false

    public init(model: LegadoAppModel, source: BookSource, onClose: (() -> Void)? = nil) {
        self.model = model
        self._source = State(initialValue: source)
        self._originalSource = State(initialValue: source)
        self.onClose = onClose
    }

    /// Closes the editor — the upstream's `finish()`.
    private let onClose: (() -> Void)?

    /// The URL field that receives the URL option.
    enum UrlOptionTarget {
        case search
        case explore
        case login
    }

    /// Whether the edited source differs from the original one — upstream
    /// `!source.equal(viewModel.bookSource ?: BookSource())`.
    private var hasChanges: Bool {
        source != originalSource
    }

    public var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: Binding(
                    get: { source.bookSourceName },
                    set: { source.bookSourceName = $0 }
                ))
                TextField("源地址", text: Binding(
                    get: { source.bookSourceUrl },
                    set: { source.bookSourceUrl = $0 }
                ))
                TextField("分组", text: Binding(
                    get: { source.bookSourceGroup ?? "" },
                    set: { source.bookSourceGroup = $0.isEmpty ? nil : $0 }
                ))
                // Upstream `binding.spType` — the type of the source
                // (`BookSourceType`).
                Picker("类型", selection: Binding(
                    get: { source.bookSourceType },
                    set: { source.bookSourceType = $0 }
                )) {
                    Text("文本").tag(BookSourceType.default)
                    Text("音频").tag(BookSourceType.audio)
                    Text("图片").tag(BookSourceType.image)
                    Text("文件").tag(BookSourceType.file)
                }
                Toggle("启用", isOn: Binding(
                    get: { source.enabled },
                    set: { source.enabled = $0 }
                ))
                Toggle("允许发现", isOn: Binding(
                    get: { source.enabledExplore },
                    set: { source.enabledExplore = $0 }
                ))
                TextField("排序", text: Binding(
                    get: { String(source.customOrder) },
                    set: { source.customOrder = Int64($0) ?? 0 }
                ))
                TextField("权重", text: Binding(
                    get: { String(source.weight) },
                    set: { source.weight = Int64($0) ?? 0 }
                ))
                TextField("备注", text: Binding(
                    get: { source.bookSourceComment ?? "" },
                    set: { source.bookSourceComment = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("高级") {
                // Upstream `BookSourceEditActivity.upSourceView` — the three
                // advanced fields of the source.
                TextField("封面解码", text: Binding(
                    get: { source.coverDecodeJs ?? "" },
                    set: { source.coverDecodeJs = $0.isEmpty ? nil : $0 }
                ))
                TextField("书籍地址正则", text: Binding(
                    get: { source.bookUrlPattern ?? "" },
                    set: { source.bookUrlPattern = $0.isEmpty ? nil : $0 }
                ))
                TextField("变量说明", text: Binding(
                    get: { source.variableComment ?? "" },
                    set: { source.variableComment = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("网络") {
                TextField("请求头", text: Binding(
                    get: { source.header ?? "" },
                    set: { source.header = $0.isEmpty ? nil : $0 }
                ))
                TextField("并发 rate", text: Binding(
                    get: { source.concurrentRate ?? "" },
                    set: { source.concurrentRate = $0.isEmpty ? nil : $0 }
                ))
                Toggle("使用 Cookie 罐", isOn: Binding(
                    get: { source.enabledCookieJar },
                    set: { source.enabledCookieJar = $0 }
                ))
                TextField("脚本库", text: Binding(
                    get: { source.jsLib ?? "" },
                    set: { source.jsLib = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("登录") {
                TextField("登录脚本", text: Binding(
                    get: { source.loginUrl ?? "" },
                    set: {
                        urlOptionTarget = .login
                        source.loginUrl = $0.isEmpty ? nil : $0
                    }
                ))
                TextField("登录界面", text: Binding(
                    get: { source.loginUi ?? "" },
                    set: { source.loginUi = $0.isEmpty ? nil : $0 }
                ))
                TextField("登录校验", text: Binding(
                    get: { source.loginCheckJs ?? "" },
                    set: { source.loginCheckJs = $0.isEmpty ? nil : $0 }
                ))
                Button("登录") {
                    model.presentLogin(for: source)
                }
            }

            Section("搜索") {
                TextField("搜索地址", text: Binding(
                    get: { source.searchUrl ?? "" },
                    set: {
                        urlOptionTarget = .search
                        source.searchUrl = $0.isEmpty ? nil : $0
                    }
                ))
                RuleTextField(title: "搜索规则", value: ruleBinding(\.ruleSearch, kind: .search))
            }

            Section("发现") {
                TextField("发现地址", text: Binding(
                    get: { source.exploreUrl ?? "" },
                    set: {
                        urlOptionTarget = .explore
                        source.exploreUrl = $0.isEmpty ? nil : $0
                    }
                ))
                RuleTextField(title: "发现规则", value: ruleBinding(\.ruleExplore, kind: .explore))
            }

            Section("详情与目录") {
                RuleTextField(title: "详情规则", value: ruleBinding(\.ruleBookInfo, kind: .bookInfo))
                RuleTextField(title: "目录规则", value: ruleBinding(\.ruleToc, kind: .toc))
                RuleTextField(title: "正文规则", value: ruleBinding(\.ruleContent, kind: .content))
            }

            Section("校验") {
                Button(isChecking ? "校验中…" : "校验书源") {
                    checkSource()
                }
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                NavigationLink("规则帮助") {
                    RuleHelpView()
                }
            }
        }
        .navigationTitle("编辑书源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    model.saveSource(source)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                // Upstream `BookSourceEditActivity.finish()` — the exit asks
                // when the source was not saved.
                Button("关闭") {
                    if hasChanges {
                        isExitConfirmed = true
                    } else {
                        onClose?()
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu("更多") {
                    // The upstream `res/menu/source_edit.xml`.
                    Button("调试") {
                        model.saveSource(source)
                        isDebugPresented = true
                    }
                    Button("清除Cookie") {
                        model.environment.cookieStore.removeCookie(url: source.bookSourceUrl)
                        message = "已清除该书源的Cookie"
                    }
                    // Upstream `menu_login` — the login of the source.
                    if let loginUrl = source.loginUrl, !loginUrl.isEmpty {
                        Button("登录") {
                            model.presentLogin(for: source)
                        }
                    }
                    // Upstream `menu_search` — the search scoped to this source.
                    Button("搜索") {
                        model.saveSource(source)
                        searchSource = source
                        isSearchPresented = true
                    }
                    Button(autoComplete ? "自动补全：开" : "自动补全：关") {
                        autoComplete.toggle()
                        message = autoComplete ? "规则将自动补全" : "规则不再自动补全"
                    }
                    Button("复制书源") {
                        UIPasteboardShim.copy(sourceJSON)
                        message = "已复制书源"
                    }
                    Button("粘贴书源") {
                        pasteSource()
                    }
                    // Upstream `menu_qr_code_camera` — the import from a QR
                    // code.
                    Button("扫码导入") {
                        isQRScannerPresented = true
                    }
                    Button("设置变量") {
                        variableText = BookSourceVariables.sourceVariables(source.key) ?? ""
                        isVariablesPresented = true
                    }
                    Button("二维码分享") {
                        isQRPresented = true
                    }
                    Button("分享") {
                        isSharePresented = true
                    }
                    NavigationLink("帮助") {
                        SourceEditorHelpView { json in
                            insertUrlOption(json)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isDebugPresented) {
            NavigationStack {
                SourceDebugView(model: model, sourceUrl: source.bookSourceUrl)
            }
        }
        .sheet(isPresented: $isVariablesPresented) {
            NavigationStack {
                VariableEditorView(
                    title: "书源变量",
                    comment: "书源变量是一个JSON对象，脚本中用 java.get('变量名') 读取。",
                    value: variableText,
                    onSave: { text in
                        saveVariables(text)
                    }
                )
            }
        }
        .sheet(isPresented: $isQRPresented) {
            NavigationStack {
                QRCodeView(text: sourceJSON)
                    .navigationTitle("书源二维码")
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [sourceJSON])
        }
        .sheet(isPresented: $isSearchPresented) {
            if let searchSource {
                NavigationStack {
                    SearchView(model: model, source: searchSource)
                }
            }
        }
        .sheet(isPresented: $isQRScannerPresented) {
            NavigationStack {
                QRScannerView(result: $qrResult)
            }
        }
        .onChange(of: qrResult) { _, value in
            guard let value, !value.isEmpty else { return }
            qrResult = nil
            importScanned(value)
        }
        .interactiveDismissDisabled(hasChanges)
        .alert("退出", isPresented: $isExitConfirmed) {
            Button("取消", role: .cancel) {}
            Button("是", role: .destructive) {
                onClose?()
            }
        } message: {
            // Upstream `R.string.exit_no_save`.
            Text("尚未保存，是否继续编辑？")
        }
    }

    /// Imports the source of a QR code — upstream `BookSourceEditActivity`'s
    /// `qrCodeResult` (the scanned text is a source JSON or a source URL).
    private func importScanned(_ text: String) {
        guard let value = try? JSONValue.parse(text),
              let scanned = BookSourceJSONBridge.decode(value) else {
            message = "二维码的内容不是一个书源"
            return
        }
        source = scanned
        message = "已导入书源"
    }

    /// The rule binding — with the auto-completion the upstream applies to
    /// every sub-rule of a rule group.
    private func ruleBinding(
        _ keyPath: WritableKeyPath<BookSource, String?>,
        kind: SourceRuleKind
    ) -> Binding<String> {
        Binding(
            get: { source[keyPath: keyPath] ?? "" },
            set: { newValue in
                var updated = source
                updated[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                if autoComplete {
                    updated[keyPath: keyPath] = RuleAutoCompleter.complete(ruleJSON: newValue, kind: kind)
                }
                source = updated
            }
        )
    }

    /// The source as a JSON document — the upstream `GSON.toJson(getSource())`.
    private var sourceJSON: String {
        BookSourceJSONBridge.encode(source).jsonString
    }

    /// Inserts the JSON of a URL option into the field that is being edited —
    /// the upstream `BookSourceEditActivity.onHelpActionSelect` inserts it into
    /// the focused field.
    private func insertUrlOption(_ json: String) {
        guard !json.isEmpty else { return }
        var updated = source
        switch urlOptionTarget {
        case .search:
            updated.searchUrl = json
        case .explore:
            updated.exploreUrl = json
        case .login:
            updated.loginUrl = json
        }
        source = updated
        message = "已插入 URL 参数"
    }

    /// Pastes a source from the clipboard — upstream `viewModel.pasteSource`.
    private func pasteSource() {
        guard let text = UIPasteboardShim.paste() else {
            message = "剪贴板为空"
            return
        }
        guard let value = try? JSONValue.parse(text),
              let pasted = BookSourceJSONBridge.decode(value) else {
            message = "剪贴板的内容不是一个书源"
            return
        }
        source.bookSourceName = pasted.bookSourceName
        source.bookSourceUrl = pasted.bookSourceUrl
        source.bookSourceGroup = pasted.bookSourceGroup
        message = "已粘贴书源：\(pasted.bookSourceName)"
    }

    /// Saves the source variables — upstream `setSourceVariable`.
    private func saveVariables(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            BookSourceVariables.clearSourceVariables(source.key)
            return
        }
        guard let value = try? JSONValue.parse(trimmed),
              let members = value.objectValue else { return }
        var variables: [String: String] = [:]
        for (name, member) in members {
            variables[name] = member.textValue
        }
        BookSourceVariables.setVariables(variables, for: source.key)
    }

    private func checkSource() {
        isChecking = true
        Task {
            let result = await SourceChecker.check(
                source: source,
                options: SourceCheckOptions(),
                dependencies: model.environment.dependencies()
            )
            await MainActor.run {
                isChecking = false
                message = result.message
                source = result.source
                model.saveSource(result.source)
            }
        }
    }
}

/// A multi-line editor for one rule (the rule JSON).
struct RuleTextField: View {

    let title: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            TextEditor(text: $value)
                .frame(minHeight: 80)
        }
    }
}

/// The rule syntax reference — upstream `assets/web/help/md/ruleHelp.md`.
public struct RuleHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(RuleHelp.text)
                .font(.system(size: 13))
                .padding()
        }
        .navigationTitle("规则帮助")
    }
}

/// The rule syntax reference.
public enum RuleHelp {

    /// The condensed rule syntax reference (the upstream `ruleHelp.md`).
    public static let text = """
    规则语法速查（节选自上游 ruleHelp.md）

    1. 规则类型由前缀决定，不会互相回退。
       · @CSS:  CSS 选择器（jsoup），规则里可以省略 @CSS: 前缀。
       · @XPath: XPath 表达式。
       · @Json:  JSONPath 表达式。
       · @js:    JavaScript 脚本，返回值作为规则结果。
       · @put:   在规则中保存一个变量，形如 @put:{key: value}。
       · @get:   读取一个变量，形如 @get:{key}。
       · {{js}}  行内 JavaScript，插入到规则文本中执行。
       · <js>…</js>  与 @js: 等价。

    2. 组合符
       · &&  与：前后都匹配才算命中。
       · ||  或：取第一个非空结果。
       · %%  交叉合并：把多段规则的结果按位置交叉排列。
       · ##  替换：规则##正则##替换文本（两段为全部替换，三段为只替换第一处）。

    3. 取值
       · getString      取文本，多个结果用换行连接。
       · getStringList  取文本列表。
       · getElements    取元素列表，配合 CSS 选择器。
       · getElement     取第一个元素。
       · @js: 后跟 JS 时，脚本里可用 result（上一个步骤的结果）、
         baseUrl、source、book、chapter 等变量。

    4. 元素选择
       · 标签.div.-1:10:2  取倒数第 1 个开始的 10 个中的第 2 个。
       · 标签.div!0:3      取排除前 3 个之后的部分。
       · 标签.div[-1, 3:-2:-10, 2]  列表式下标，支持倒序。
       · @CSS:div@p     取属性（@text 取文本，@html 取源码）。
       · @CSS:div@href  取链接地址。

    5. JSONPath
       · $.data.list[0].title  取字段。
       · $.data.list[?(@.id==1)]  过滤。
       · $..name  递归查找。

    6. 变量
       · @put:{token} 保存，@get:{token} 读取，变量在同一个源内共享。
       · java.ajax / java.get / java.post 可在脚本里发请求。
       · java.put / java.get 可读写源变量。

    7. 换源与校验
       · 校验会依次检查搜索、发现、详情、目录和正文。
       · 换源按书名搜索，作者可选校验，结果按书源评分排序。
    """
}
