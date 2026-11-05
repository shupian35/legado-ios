//
//  SharedText.swift
//  LegadoCore
//
//  The text that another app shares with the port — the port of
//  app/src/main/java/io/legado/app/receiver/SharedReceiverActivity.kt.
//
//  Upstream the Android app registers a receiver for `ACTION_SEND` and
//  `ACTION_PROCESS_TEXT` with the type `text/plain`; the shared text is
//  inspected: when it contains an address the app is opened with it, and
//  everything else is searched for.
//
//  The iOS equivalent is a share extension; the decision itself lives here so
//  that it can be unit-tested.
//

import Foundation

/// What the port does with a shared text — upstream `SharedReceiverActivity`.
public enum SharedTextAction: Equatable, Sendable {
    /// The text contains an address: the app imports it — upstream
    /// `dispose(text)` opens the main activity.
    case importAddress(String)
    /// The text is a search term — upstream `SearchActivity.start(this, text)`.
    case search(String)
    /// The text asks for the read aloud — upstream the `readAloud` extra.
    case readAloud
    /// The text is empty — upstream `dispose(text)` returns for a blank text.
    case none
}

/// The shared text — upstream `SharedReceiverActivity.dispose`.
public enum SharedText {

    /// The extra the upstream uses for the read aloud — upstream
    /// `intent.getStringExtra("action") == "readAloud"`.
    public static let readAloudAction = "readAloud"

    /// Decides what to do with a shared text.
    ///
    /// Upstream splits the text on the white space, keeps the parts that match
    /// `http.+` and opens the main activity when there is at least one of
    /// them; otherwise the whole text is searched for.
    public static func action(for text: String) -> SharedTextAction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let parts = trimmed
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .map(String.init)
        let addresses = parts.filter { $0.lowercased().hasPrefix("http") }
        if let address = addresses.first {
            return .importAddress(address)
        }
        return .search(trimmed)
    }

    /// The deep link that opens the app for an action.
    ///
    /// The import link is the upstream's `legado://importonline?src=…` format;
    /// the search link is the port's own `legado://search?key=…`.
    public static func deepLink(for action: SharedTextAction) -> URL? {
        switch action {
        case .importAddress(let address):
            var components = URLComponents()
            components.scheme = DeepLink.scheme
            components.host = "importonline"
            components.queryItems = [URLQueryItem(name: "src", value: address)]
            return components.url
        case .search(let keyword):
            var components = URLComponents()
            components.scheme = DeepLink.scheme
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "key", value: keyword)]
            return components.url
        case .readAloud:
            var components = URLComponents()
            components.scheme = DeepLink.scheme
            components.host = "shortcut"
            components.path = "/readAloud"
            return components.url
        case .none:
            return nil
        }
    }
}

/// The search keyword of a link — the port's own `legado://search?key=…`.
///
/// Upstream the shared text is searched for in `SearchActivity`; the port
/// opens the same screen through a link.
public enum DeepLinkSearch {

    /// The keyword of a link, or `nil` when the link is not a search link.
    public static func keyword(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), DeepLink.schemes.contains(scheme) else {
            return nil
        }
        guard url.host?.lowercased() == "search" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let keyword = components?.queryItems?.first { $0.name == "key" }?.value ?? ""
        return keyword.isEmpty ? nil : keyword
    }
}
