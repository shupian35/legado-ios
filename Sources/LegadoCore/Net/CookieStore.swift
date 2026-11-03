//
//  CookieStore.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/help/http/CookieStore.kt.
//

import Foundation

/// Persists the cookies of a domain.
public protocol CookiePersisting: AnyObject {
    func cookie(forDomain domain: String) -> String?
    func setCookie(_ cookie: String, forDomain domain: String)
    func removeCookie(forDomain domain: String)
    /// Every domain that holds a cookie — used to seed a web view.
    func allDomains() -> [String]
}

/// A stored cookie of the jar.
public struct StoredCookie: Equatable, Sendable {
    /// The registrable domain the cookie belongs to.
    public let domain: String
    /// The raw `key=value; key2=value2` header value.
    public let value: String

    public init(domain: String, value: String) {
        self.domain = domain
        self.value = value
    }

    /// The individual cookies of the jar.
    public var pairs: [(key: String, value: String)] {
        value.split(separator: ";").compactMap { pair in
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: "=") else { return nil }
            let key = String(trimmed[trimmed.startIndex..<separator])
            let val = String(trimmed[trimmed.index(after: separator)...])
            return (key, val)
        }
    }
}

/// An in-memory `CookiePersisting` — used by the tests and as a fallback.
public final class MemoryCookiePersistence: CookiePersisting {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func cookie(forDomain domain: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[domain]
    }

    public func setCookie(_ cookie: String, forDomain domain: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[domain] = cookie
    }

    public func removeCookie(forDomain domain: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: domain)
    }

    public func allDomains() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.keys)
    }
}

/// An insertion ordered key/value map.
///
/// The upstream stores the cookies in a `HashMap`, so its order is
/// arbitrary; the port keeps the insertion order, which makes the emitted
/// `Cookie` header stable.
public struct CookieMap {
    /// The keys in insertion order.
    public private(set) var order: [String] = []
    private var values: [String: String] = [:]

    public init() {}

    public subscript(key: String) -> String? {
        get { values[key] }
        set {
            if let newValue {
                if values[key] == nil { order.append(key) }
                values[key] = newValue
            } else {
                values.removeValue(forKey: key)
                order.removeAll { $0 == key }
            }
        }
    }

    public var isEmpty: Bool { order.isEmpty }
    public var count: Int { order.count }
    public var keys: [String] { order }

    /// Merge `other` into the map — the values of `other` win.
    public mutating func merge(_ other: CookieMap) {
        for key in other.order {
            self[key] = other[key]
        }
    }
}

/// A `CookiePersisting` that keeps the cookies in the user defaults.
///
/// Upstream stores them in the SharedPreferences (`CookieStore.kt:25-71`), so
/// the cookies survive a restart of the app.
public final class UserDefaultsCookiePersistence: CookiePersisting {
    private let defaults: UserDefaults
    private let prefix: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, prefix: String = "cookie_") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func cookie(forDomain domain: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: prefix + domain)
    }

    public func setCookie(_ cookie: String, forDomain domain: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(cookie, forKey: prefix + domain)
    }

    public func removeCookie(forDomain domain: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: prefix + domain)
    }

    public func allDomains() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

/// The cookie jar — the port of `io.legado.app.help.http.CookieStore`.
public final class CookieStore {
    private let persistence: CookiePersisting
    /// The in-memory session cookies (upstream `CookieManager`).
    private var sessionCookies: [String: CookieMap] = [:]
    private let lock = NSLock()

    public init(persistence: CookiePersisting = MemoryCookiePersistence()) {
        self.persistence = persistence
    }

    /// Store a cookie for the registrable domain of `url`.
    public func setCookie(url: String, cookie: String?) {
        let domain = NetworkUtils.subDomain(url)
        persistence.setCookie(cookie ?? "", forDomain: domain)
    }

    /// Merge a cookie into the stored one.
    public func replaceCookie(url: String, cookie: String) {
        if url.isEmpty || cookie.isEmpty { return }
        let old = cookieNoSession(url: url)
        if old.isEmpty {
            setCookie(url: url, cookie: cookie)
        } else {
            var map = cookieToMap(old)
            map.merge(cookieToMap(cookie))
            setCookie(url: url, cookie: mapToCookie(map) ?? "")
        }
    }

    /// The cookie header value for `url`.
    public func cookie(url: String) -> String {
        let domain = NetworkUtils.subDomain(url)
        let stored = cookieNoSession(url: url)
        let session = sessionCookie(domain: domain)
        var map = mergeCookiesToMap(stored, mapToCookie(session))
        var text = mapToCookie(map) ?? ""
        while text.count > 4096, let key = map.order.randomElement() {
            map[key] = nil
            removeSessionCookie(domain: domain, key: key)
            text = mapToCookie(map) ?? ""
        }
        return text
    }

    /// The value of a single cookie of `url`.
    public func key(url: String, key: String) -> String {
        let domain = NetworkUtils.subDomain(url)
        let map = mergeCookiesToMap(
            cookieNoSession(url: url),
            mapToCookie(sessionCookie(domain: domain))
        )
        return map[key] ?? ""
    }

    /// Every stored cookie of the jar — used to seed a web view.
    ///
    /// The upstream shares one global cookie manager between the app and the
    /// web view; on iOS the cookies are copied over explicitly.
    public func allCookies() -> [StoredCookie] {
        var result: [StoredCookie] = []
        for domain in persistence.allDomains() {
            guard let cookie = persistence.cookie(forDomain: domain), !cookie.isEmpty else { continue }
            result.append(StoredCookie(domain: domain, value: cookie))
        }
        for (domain, map) in sessionCookies {
            guard let cookie = mapToCookie(map), !cookie.isEmpty else { continue }
            result.append(StoredCookie(domain: domain, value: cookie))
        }
        return result
    }

    /// Remove every cookie of `url`.
    public func removeCookie(url: String) {
        let domain = NetworkUtils.subDomain(url)
        persistence.removeCookie(forDomain: domain)
        lock.lock()
        sessionCookies.removeValue(forKey: domain)
        lock.unlock()
    }

    // MARK: - Session cookies

    public func setSessionCookie(domain: String, key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        sessionCookies[domain, default: CookieMap()][key] = value
    }

    public func removeSessionCookie(domain: String, key: String) {
        lock.lock()
        defer { lock.unlock() }
        sessionCookies[domain]?[key] = nil
    }

    public func sessionCookie(domain: String) -> CookieMap {
        lock.lock()
        defer { lock.unlock() }
        return sessionCookies[domain] ?? CookieMap()
    }

    // MARK: - Parsing

    /// Split a cookie header into its key/value pairs.
    public func cookieToMap(_ cookie: String) -> CookieMap {
        var map = CookieMap()
        if cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return map }
        for pair in cookie.split(separator: ";", omittingEmptySubsequences: false) {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator])
                .trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty || value == "null" {
                map[key] = value
            }
        }
        return map
    }

    /// Join key/value pairs into a cookie header.
    public func mapToCookie(_ map: CookieMap?) -> String? {
        guard let map, !map.isEmpty else { return nil }
        return map.order.map { "\($0)=\(map[$0] ?? "")" }.joined(separator: "; ")
    }

    /// Merge two cookie maps — the later one wins.
    public func mergeCookiesToMap(_ first: String?, _ second: String?) -> CookieMap {
        var map = cookieToMap(first ?? "")
        map.merge(cookieToMap(second ?? ""))
        return map
    }

    private func cookieNoSession(url: String) -> String {
        let domain = NetworkUtils.subDomain(url)
        return persistence.cookie(forDomain: domain) ?? ""
    }
}
