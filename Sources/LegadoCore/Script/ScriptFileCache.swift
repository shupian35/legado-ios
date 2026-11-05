//
//  ScriptFileCache.swift
//  LegadoCore
//
//  The file downloads of the rule scripts — the port of upstream
//  `app/src/main/java/io/legado/app/help/JsExtensions.kt`:
//  `downloadFile(url)` and `cacheFile(urlStr, saveTime)`.
//
//  The logic lives here (and not in the `java` facade) so that it can be
//  tested on every platform — the facade itself is JavaScriptCore only.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/JsExtensions.kt:278-344
//  app/src/main/java/io/legado/app/utils/UrlUtil.kt:151-168
//

import Foundation

/// The files the rule scripts download.
///
/// Upstream the `java.downloadFile(url)` writes the file into the cache
/// directory of the app under the name `<md5 of the url>.<type>` and returns
/// the path RELATIVE to the cache directory; `java.cacheFile(url, saveTime)`
/// keeps the file in the `CacheManager` under the key `<md5 of the url>` and
/// returns the TEXT of the file.
public final class ScriptFileCache: @unchecked Sendable {

    private let lock = NSLock()
    /// The cached files — the key is the `md5Encode16` of the address.
    private var entries: [String: (path: String, expiry: Date?)] = [:]

    public init() {}

    // MARK: - The names

    /// The name of the downloaded file — upstream
    /// `"${MD5Utils.md5Encode16(url)}.${type}"`.
    ///
    /// The type comes from the option block of the address (the upstream
    /// `AnalyzeUrl(url).type`); when the address does not carry one the
    /// suffix of the path is used (`UrlUtil.getSuffix`).
    public static func downloadFileName(for url: String) -> String {
        let type = AnalyzeUrl.option(of: url)?.type ?? ""
        let suffix = type.isEmpty ? WebFileBook.suffix(of: url) : type
        return "\(ScriptDigest.md5Encode16(url)).\(suffix)"
    }

    // MARK: - The downloads

    /// Upstream `JsExtensions.downloadFile(url)`.
    ///
    /// - Returns: the path of the file relative to the sandbox directory
    ///   (the upstream returns the path relative to the cache directory).
    public func download(
        url: String,
        client: ScriptNetworkClient,
        files: ScriptFileSandbox,
        headers: [String: String] = [:]
    ) throws -> String {
        let data = try client.scriptDownload(url, headers: headers)
        let name = Self.downloadFileName(for: url)
        // The upstream deletes the file before it writes it.
        try files.writeScriptData(name, data: data)
        return "/" + name
    }

    /// Upstream `JsExtensions.cacheFile(urlStr, saveTime)`.
    ///
    /// - Returns: the TEXT of the cached file.
    public func cacheFile(
        url: String,
        saveTime: Int,
        client: ScriptNetworkClient,
        files: ScriptFileSandbox,
        headers: [String: String] = [:]
    ) throws -> String {
        let key = ScriptDigest.md5Encode16(url)
        if let path = cachedPath(for: key),
           let text = readCachedFile(path, files: files) {
            return text
        }
        let path = try download(url: url, client: client, files: files, headers: headers)
        remember(path: path, for: key, saveTime: saveTime)
        return readCachedFile(path, files: files) ?? ""
    }

    // MARK: - The cache

    /// The path of a cached file — `nil` when it is not cached (any more).
    public func cachedPath(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        if let expiry = entry.expiry, expiry < Date() {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.path
    }

    /// Remembers a downloaded file — upstream `CacheManager.put(key, path, saveTime)`.
    public func remember(path: String, for key: String, saveTime: Int) {
        lock.lock()
        defer { lock.unlock() }
        let expiry = saveTime > 0 ? Date().addingTimeInterval(TimeInterval(saveTime)) : nil
        entries[key] = (path: path, expiry: expiry)
    }

    /// Forgets the cached files.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    private func readCachedFile(_ path: String, files: ScriptFileSandbox) -> String? {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return try? files.readScriptFile(relative)
    }
}
