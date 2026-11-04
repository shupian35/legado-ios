//
//  SourceEditorHelpViews.swift
//  LegadoUI
//
//  The help actions of the source editor.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/edit/BookSourceEditActivity.kt:587-624
//  app/src/main/java/io/legado/app/ui/widget/dialog/UrlOptionDialog.kt
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The URL option editor — upstream `ui/widget/dialog/UrlOptionDialog.kt`.
/// The OK hands the JSON of the option block to the caller, which inserts it
/// into the field that is being edited (the upstream inserts it into the
/// focused field).
public struct UrlOptionEditorView: View {

    /// The JSON of the option block.
    let onInsert: (String) -> Void

    @State private var method: String = "GET"
    @State private var charset: String = "UTF-8"
    @State private var headers: String = ""
    /// The request body — it cannot be called `body`, the view has one.
    @State private var requestBody: String = ""
    @State private var retry: String = ""
    @State private var type: String = ""
    @State private var webJs: String = ""
    @State private var js: String = ""
    @State private var useWebView: Bool = false

    public init(onInsert: @escaping (String) -> Void) {
        self.onInsert = onInsert
    }

    public var body: some View {
        Form {
            Section("请求") {
                Picker("请求方式", selection: $method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                }
                Picker("字符集", selection: $charset) {
                    ForEach(UrlOption.charsets, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("重试次数", text: $retry)
                TextField("类型", text: $type)
            }
            Section("内容") {
                TextField("请求头（JSON）", text: $headers)
                TextField("请求体", text: $requestBody)
            }
            Section("脚本") {
                TextField("WebView 中的 js", text: $webJs)
                TextField("解析完 url 后执行的 js", text: $js)
                Toggle("使用 WebView", isOn: $useWebView)
            }
        }
        .navigationTitle("插入URL参数")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    onInsert("")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("确定") {
                    onInsert(option.jsonString())
                }
            }
        }
    }

    /// The option block of the form.
    private var option: UrlOption {
        var headerMap: [String: String]?
        let trimmedHeaders = headers.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHeaders.isEmpty {
            if let value = try? JSONValue.parse(trimmedHeaders),
               case .object(let object) = value {
                var map: [String: String] = [:]
                for (key, item) in object {
                    map[key] = item.stringValue ?? ""
                }
                headerMap = map
            }
        }
        return UrlOption(
            method: method,
            charset: charset,
            headers: headerMap,
            body: requestBody.isEmpty ? nil : requestBody,
            retry: Int(retry.trimmingCharacters(in: .whitespaces)),
            type: type.isEmpty ? nil : type,
            useWebView: useWebView,
            webJs: webJs.isEmpty ? nil : webJs,
            js: js.isEmpty ? nil : js
        )
    }
}

/// The help actions of the source editor — upstream
/// `BookSourceEditActivity.helpActions()`: 插入URL参数 / 书源教程 / js教程 /
/// 正则教程.
public struct SourceEditorHelpView: View {

    /// The JSON of the URL option is inserted into the field that is being
    /// edited (the upstream inserts it into the focused field).
    let onInsertUrlOption: (String) -> Void

    @State private var isUrlOptionPresented = false

    public init(onInsertUrlOption: @escaping (String) -> Void) {
        self.onInsertUrlOption = onInsertUrlOption
    }

    public var body: some View {
        List {
            Section("帮助") {
                NavigationLink("书源教程") {
                    MarkdownView(title: "书源教程", markdown: SourceEditorHelp.ruleHelp)
                }
                NavigationLink("js教程") {
                    MarkdownView(title: "js教程", markdown: SourceEditorHelp.jsHelp)
                }
                NavigationLink("正则教程") {
                    MarkdownView(title: "正则教程", markdown: SourceEditorHelp.regexHelp)
                }
                Button("插入URL参数") {
                    isUrlOptionPresented = true
                }
            }
        }
        .navigationTitle("帮助")
        .sheet(isPresented: $isUrlOptionPresented) {
            NavigationStack {
                UrlOptionEditorView { json in
                    isUrlOptionPresented = false
                    if !json.isEmpty {
                        onInsertUrlOption(json)
                    }
                }
            }
        }
    }
}
