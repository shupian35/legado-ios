//
//  OpenUrlConfirmView.swift
//  LegadoUI
//
//  The confirmation of an external link — the port of
//  app/src/main/java/io/legado/app/ui/association/OpenUrlConfirmDialog.kt.
//
//  Upstream a rule script that calls `java.openUrl(url, mimeType)` starts the
//  confirmation activity: the dialog asks the user whether the jump may
//  happen and offers to disable or to delete the source that asked.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The confirmation of an external link — upstream `OpenUrlConfirmDialog`.
public struct OpenUrlConfirmView: View {

    @ObservedObject var model: LegadoAppModel
    /// The jump that was asked for.
    let request: OpenURLRequest

    /// Opens the link with the system browser.
    @Environment(\.openURL) private var openURL
    /// Whether the deletion of the source is confirmed.
    @State private var isDeleteAlertPresented = false

    public init(model: LegadoAppModel, request: OpenURLRequest) {
        self.model = model
        self.request = request
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(request.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text(request.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                HStack {
                    Button("取消") {
                        model.cancelOpenURL()
                    }
                    .buttonStyle(.bordered)
                    Button("确定") {
                        accept()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("跳转确认")
            .legadoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("更多") {
                        // Upstream `R.menu.open_url_confirm`:
                        // `menu_disable_source` and `menu_delete_source`.
                        Button("禁用书源") {
                            disableSource()
                        }
                        Button("删除书源", role: .destructive) {
                            isDeleteAlertPresented = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "确定删除",
                isPresented: $isDeleteAlertPresented
            ) {
                Button("确定", role: .destructive) {
                    deleteSource()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定删除\n\(request.sourceName)")
            }
        }
    }

    /// Opens the link — upstream `openUrl()`.
    private func accept() {
        let url = request.url
        model.confirmOpenURL()
        if let link = URL(string: url) {
            openURL(link)
        }
    }

    /// Disables the source that asked — upstream
    /// `OpenUrlConfirmViewModel.disableSource`.
    private func disableSource() {
        guard let key = request.sourceKey, !key.isEmpty else { return }
        if let source = try? model.environment.store.source(url: key) {
            model.setSource(source, enabled: false)
        }
        model.cancelOpenURL()
    }

    /// Deletes the source that asked — upstream
    /// `OpenUrlConfirmViewModel.deleteSource`.
    private func deleteSource() {
        guard let key = request.sourceKey, !key.isEmpty else { return }
        if let source = try? model.environment.store.source(url: key) {
            model.deleteSource(source)
        }
        model.cancelOpenURL()
    }
}
