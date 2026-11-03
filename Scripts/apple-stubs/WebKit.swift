//
//  WebKit.swift
//  apple-stubs
//
//  A **type-check only** stand-in for WebKit.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//

import Foundation
import FoundationNetworking

// MARK: - The navigation

/// `WebKit.WKNavigation`.
open class WKNavigation: NSObject {}

/// `WebKit.WKNavigationActionPolicy`.
public enum WKNavigationActionPolicy: Int {
    case cancel = 0
    case allow = 1
}

/// `WebKit.WKNavigationAction`.
open class WKNavigationAction: NSObject {
    open var request: URLRequest { URLRequest(url: URL(string: "about:blank")!) }
}

/// `WebKit.WKNavigationDelegate`.
///
/// The real protocol declares its methods as `@objc optional` — the stub
/// gives them default implementations so that a conformer only implements
/// what it needs.
public protocol WKNavigationDelegate: AnyObject {}

public extension WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {}
}

/// `WebKit.WKUIDelegate`.
public protocol WKUIDelegate: AnyObject {}

// MARK: - The cookies

/// `WebKit.WKHTTPCookieStore`.
open class WKHTTPCookieStore: NSObject {
    open func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)? = nil) {}
    open func setCookies(_ cookies: [HTTPCookie], completionHandler: (() -> Void)? = nil) {}
    open func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) { completionHandler([]) }
    open func getCookies(for URL: URL, completionHandler: @escaping ([HTTPCookie]) -> Void) { completionHandler([]) }
    open func deleteAllCookies(_ completionHandler: (() -> Void)? = nil) { completionHandler?() }
}

/// `WebKit.WKWebsiteDataStore`.
open class WKWebsiteDataStore: NSObject {
    open class func `default`() -> WKWebsiteDataStore { WKWebsiteDataStore() }
    open class func nonPersistent() -> WKWebsiteDataStore { WKWebsiteDataStore() }
    open var httpCookieStore: WKHTTPCookieStore { WKHTTPCookieStore() }
}

// MARK: - The web view

/// `WebKit.WKPreferences`.
open class WKPreferences: NSObject {
    open var javaScriptEnabled: Bool = true
    open var javaScriptCanOpenWindowsAutomatically: Bool = false
    public override init() { super.init() }
}

/// `WebKit.WKWebViewConfiguration`.
open class WKWebViewConfiguration: NSObject {
    open var websiteDataStore: WKWebsiteDataStore = WKWebsiteDataStore()
    open var preferences: WKPreferences = WKPreferences()
    open var allowsInlineMediaPlayback: Bool = false
    open var javaScriptCanOpenWindowsAutomatically: Bool = false
    public override init() { super.init() }
}

/// `WebKit.WKWebView`.
open class WKWebView: NSObject {
    open var configuration: WKWebViewConfiguration { WKWebViewConfiguration() }
    open weak var navigationDelegate: WKNavigationDelegate?
    open weak var uiDelegate: WKUIDelegate?
    open var url: URL?
    open var title: String?
    open var isLoading: Bool { false }

    public init(frame: CGRect, configuration: WKWebViewConfiguration) { super.init() }
    public convenience init(frame: CGRect) { self.init(frame: frame, configuration: WKWebViewConfiguration()) }

    @discardableResult
    open func load(_ request: URLRequest) -> WKNavigation? { WKNavigation() }
    @discardableResult
    open func loadHTMLString(_ htmlString: String, baseURL: URL?) -> WKNavigation? { WKNavigation() }
    open func reload() {}
    open func stopLoading() {}
    open func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {}
}
