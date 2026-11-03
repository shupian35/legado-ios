//
//  SourceLoginView.swift
//  LegadoUI
//
//  Port of `app/src/main/java/io/legado/app/ui/login/SourceLoginDialog.kt`
//  (the login form of a book source) and of
//  `app/src/main/java/io/legado/app/ui/login/SourceLoginActivity.kt` (the
//  choice between the form and the web view).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

/// The login form of a source — upstream `SourceLoginDialog`.
public struct SourceLoginView: View {

    /// The source that is logged in.
    public let source: BookSource
    /// The login service.
    @ObservedObject var model: LegadoAppModel

    @State private var values: [String: String] = [:]
    @State private var message: String?
    @State private var isWorking = false
    @State private var showsWebLogin = false

    public init(source: BookSource, model: LegadoAppModel) {
        self.source = source
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Section("登录信息") {
                    ForEach(rows, id: \.name) { row in
                        loginRow(row)
                    }
                }
                Section {
                    Button("登录") {
                        Task { await performLogin() }
                    }
                    .disabled(isWorking)
                    Button("清除登录信息") {
                        Task { await clearLogin() }
                    }
                }
            }
            .navigationTitle("登录书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        model.dismissPresentedSheet()
                    }
                }
            }
            .onAppear {
                loadStoredInfo()
            }
        }
        .sheet(isPresented: $showsWebLogin) {
            if let url = URL(string: source.loginUrl ?? "") {
                WebLoginView(url: url, cookieStore: model.environment.cookieStore)
            }
        }
    }

    /// The rows of the login UI — upstream `source.loginUi()`.
    private var rows: [RowUi] {
        model.environment.loginService.loginUi(for: source)
    }

    @ViewBuilder
    private func loginRow(_ row: RowUi) -> some View {
        if row.type == RowUi.Kind.button {
            Button(row.name) {
                runButton(row)
            }
        } else if row.type == RowUi.Kind.password {
            SecureField(row.name, text: binding(for: row))
                .textFieldStyle(.roundedBorder)
        } else {
            TextField(row.name, text: binding(for: row))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for row: RowUi) -> Binding<String> {
        Binding(
            get: { values[row.name] ?? "" },
            set: { values[row.name] = $0 }
        )
    }

    /// Fills the form with the stored login information.
    private func loadStoredInfo() {
        guard let info = try? model.environment.loginService.loginInfo(for: source.key) else { return }
        values = info
    }

    /// Stores the login information and runs the login script.
    private func performLogin() async {
        isWorking = true
        defer { isWorking = false }
        let service = model.environment.loginService
        do {
            if values.isEmpty {
                try service.removeLoginInfo(for: source.key)
                message = "已清除登录信息"
            } else {
                try service.putLoginInfo(values, for: source.key)
                service.currentKey = source.key
                _ = try service.login(source: source, loginData: values)
                message = "登录成功"
            }
        } catch {
            message = "登录出错\n\(error.localizedDescription)"
        }
    }

    /// Removes the stored login information and the login header.
    private func clearLogin() async {
        let service = model.environment.loginService
        try? service.removeLoginInfo(for: source.key)
        try? service.removeLoginHeader(for: source.key)
        values = [:]
        message = "已清除登录信息"
    }

    /// Runs the action of a login UI button.
    private func runButton(_ row: RowUi) {
        guard let action = SourceLoginService.buttonAction(row) else { return }
        switch action {
        case .openURL(let url):
            showsWebLogin = true
        case .script(let script):
            let service = model.environment.loginService
            service.currentKey = source.key
            do {
                _ = try service.runButtonScript(source: source, script: script, loginData: values)
                message = "已执行"
            } catch {
                message = "执行出错\n\(error.localizedDescription)"
            }
        }
    }
}
