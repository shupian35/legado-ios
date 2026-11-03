//
//  LocalPasswordView.swift
//  LegadoUI
//
//  The local password — upstream `help/config/LocalConfig.kt` and the prompt
//  of `ui/main/MainActivity.kt` (`setLocalPassword`).
//
//  The password is the key of the encrypted parts of a backup (upstream
//  `help/storage/BackupAES.kt`); it is stored in its own preferences file so
//  that it never travels with a backup.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The editor of the local password.
public struct LocalPasswordView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var password = ""
    @State private var message: String?
    /// Whether the view may be closed without setting a password.
    @State private var allowsCancel: Bool

    public init(model: LegadoAppModel, allowsCancel: Bool = true) {
        self.model = model
        self.allowsCancel = allowsCancel
    }

    public var body: some View {
        Form {
            Section("本地密码") {
                SecureField("密码", text: $password)
                Text("用于加密备份中的敏感信息（如 WebDAV 配置）。密码保存在本机，不会写入备份。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Section {
                Button("保存") {
                    save()
                }
                if allowsCancel {
                    Button("取消") {
                        // The upstream stores an empty password when the user
                        // declines, so the prompt is not shown again.
                        model.environment.localConfig.password = ""
                        model.isLocalPasswordPresented = false
                    }
                }
            }
            if let message {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("本地密码")
        .onAppear {
            password = model.environment.localConfig.password ?? ""
        }
    }

    private func save() {
        model.environment.localConfig.password = password
        model.isLocalPasswordPresented = false
        message = "已保存"
    }
}
