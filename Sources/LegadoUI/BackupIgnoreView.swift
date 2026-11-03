//
//  BackupIgnoreView.swift
//  LegadoUI
//
//  The "恢复时忽略的备份项" screen — upstream
//  `ui/config/BackupConfigFragment.kt` → the `restore_ignore` dialog and
//  `help/storage/BackupConfig.kt`.
//
//  Every group can be excluded from a restore; the preferences of the group
//  are then left untouched.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The list of the configuration groups that a restore skips.
public struct BackupIgnoreConfigView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var config = BackupIgnoreConfig()

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("恢复时忽略的备份项") {
                ForEach(BackupIgnoreKey.allCases) { key in
                    Toggle(key.title, isOn: Binding(
                        get: { config.isIgnored(key) },
                        set: { value in
                            config.set(value, for: key)
                            config.save(to: model.environment.settings.settingsStore)
                        }
                    ))
                }
            }
            Section {
                Text("恢复时，被忽略的项目将保留当前设置。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("恢复时忽略的备份项")
        .onAppear {
            config = BackupIgnoreConfig.load(from: model.environment.settings.settingsStore)
        }
    }
}

/// The "清除缓存" action — upstream `ui/config/OtherConfigFragment.clearCache()`
/// → `ConfigViewModel.clearCache()` → `BookHelp.clearCache()`.
public struct ClearCacheButton: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isConfirming = false
    @State private var status: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Button("清除缓存") {
            isConfirming = true
        }
        .confirmationDialog("确定删除?", isPresented: $isConfirming) {
            Button("清除缓存") {
                clear()
            }
            Button("取消", role: ButtonRole.cancel) {}
        }
        .alert("提示", isPresented: Binding(
            get: { status != nil },
            set: { if !$0 { status = nil } }
        )) {
            Button("好") {
                status = nil
            }
        }
    }

    private func clear() {
        model.environment.cacheStorage?.clearAllCache()
        status = "缓存已清除"
    }
}
