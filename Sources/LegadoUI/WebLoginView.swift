//
//  WebLoginView.swift
//  LegadoUI
//
//  Port of `app/src/main/java/io/legado/app/ui/login/WebViewLoginFragment.kt`:
//  a source without a login UI is logged in through a web view. The upstream
//  shares the app cookie jar with the web view (the Android CookieManager is
//  global); on iOS the cookies are copied between the WKWebView cookie store
//  and the port's cookie jar.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

#if canImport(FoundationNetworking)
// `HTTPCookie` and `URLRequest` live in FoundationNetworking on Linux.
import FoundationNetworking
#endif

#if canImport(WebKit)
import WebKit

/// The web view login — upstream `WebViewLoginFragment`.
public struct WebLoginView: View {

    private let url: URL
    private let cookieStore: CookieStore
    @State private var coordinator = LoginCoordinator()

    public init(url: URL, cookieStore: CookieStore) {
        self.url = url
        self.cookieStore = cookieStore
    }

    public var body: some View {
        NavigationStack {
            WebKitView(url: url, coordinator: coordinator, cookieStore: cookieStore)
                .navigationTitle("登录")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            coordinator.onClose?()
                        }
                    }
                }
        }
    }

    /// The coordinator that copies the cookies in and out of the web view.
    final class LoginCoordinator: NSObject, WKNavigationDelegate {
        var onClose: (() -> Void)?
        private weak var webView: WKWebView?
        private var cookieStore: CookieStore?

        func attach(_ webView: WKWebView, cookieStore: CookieStore) {
            self.webView = webView
            self.cookieStore = cookieStore
        }

        /// Sends the cookies of the app to the web view.
        func seedCookies() {
            guard let webView, let cookieStore else { return }
            var items: [HTTPCookie] = []
            for stored in cookieStore.allCookies() {
                for pair in stored.pairs {
                    // `HTTPCookie.init?(properties:)` takes the typed keys.
                    var properties: [HTTPCookiePropertyKey: Any] = [
                        .name: pair.key,
                        .value: pair.value,
                        .domain: stored.domain,
                        .path: "/"
                    ]
                    properties[.domain] = "." + stored.domain
                    if let item = HTTPCookie(properties: properties) { items.append(item) }
                }
            }
            // `setCookies(_:completionHandler:)` needs iOS 26 / macOS 26;
            // `setCookie(_:)` is available on every supported version.
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for item in items {
                store.setCookie(item)
            }
        }

        /// Copies the cookies of the web view into the app.
        func collectCookies() {
            guard let webView, let cookieStore else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    cookieStore.setCookie(
                        url: "https://\(cookie.domain)\(cookie.path)",
                        cookie: "\(cookie.name)=\(cookie.value)"
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            collectCookies()
        }
    }
}

/// The WKWebView wrapper.
struct WebKitView {

    let url: URL
    let coordinator: WebLoginView.LoginCoordinator
    let cookieStore: CookieStore

    func makeCoordinator() -> WebLoginView.LoginCoordinator { coordinator }

    /// The shared setup — the `UIView` and the `NSView` wrapper only differ in
    /// the name of the platform view.
    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.attach(webView, cookieStore: cookieStore)
        coordinator.seedCookies()
        webView.load(URLRequest(url: url))
        return webView
    }
}

#if canImport(UIKit)
extension WebKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
extension WebKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

#else

/// The web view login — the Linux stand-in (no WebKit there).
public struct WebLoginView: View {

    private let url: URL
    private let cookieStore: CookieStore

    public init(url: URL, cookieStore: CookieStore) {
        self.url = url
        self.cookieStore = cookieStore
    }

    public var body: some View {
        Text("WebKit is only available on Apple platforms")
    }
}

#endif
