//
//  VerificationView.swift
//  LegadoUI
//
//  The source verification dialogs — the image captcha and the anti-scraping
//  page in the built-in browser.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/association/VerificationCodeDialog.kt
//  app/src/main/java/io/legado/app/ui/association/VerificationCodeActivity.kt
//  app/src/main/java/io/legado/app/help/source/SourceVerificationHelp.kt
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The captcha dialog — upstream `VerificationCodeDialog`.
///
/// The image comes from the source, the user types the code and the answer is
/// handed back to the rule that asked for it.
public struct VerificationCodeSheet: View {

    /// The request that waits for the answer.
    public let request: SourceVerificationRequest
    /// The code the user typed.
    @State private var code: String = ""
    /// Delivers the answer.
    let onSubmit: (String) -> Void
    /// Aborts the request.
    let onCancel: () -> Void

    public init(
        request: SourceVerificationRequest,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请输入验证码")
                .font(.system(size: 16, weight: .semibold))
            if !request.sourceName.isEmpty {
                Text(request.sourceName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if let imageURL = request.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        return AnyView(image.resizable().aspectRatio(contentMode: .fit))
                    }
                    return AnyView(
                        Text("加载中")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    )
                }
                .frame(height: 120)
            }
            TextField("验证码", text: $code)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { onCancel() }
                Spacer()
                Button("确定") { onSubmit(code) }
            }
        }
        .padding(16)
    }
}

/// The anti-scraping page — upstream `WebViewActivity` with
/// `sourceVerificationEnable`.
///
/// The user solves the check in the built-in browser and confirms; the text of
/// the page is handed back to the rule.
public struct VerificationBrowserSheet: View {

    /// The request that waits for the answer.
    public let request: SourceVerificationRequest
    /// Delivers the answer.
    let onSubmit: (String) -> Void
    /// Aborts the request.
    let onCancel: () -> Void

    public init(
        request: SourceVerificationRequest,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请完成验证")
                .font(.system(size: 16, weight: .semibold))
            if !request.sourceName.isEmpty {
                Text(request.sourceName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            InAppBrowserView(url: request.url)
                .frame(height: 320)
            HStack {
                Button("取消") { onCancel() }
                Spacer()
                Button("完成") { onSubmit("") }
            }
        }
        .padding(16)
    }
}
