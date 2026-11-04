//
//  SourceConfig.swift
//  LegadoCore
//
//  The user rating of the books of a source — the "好评 / 差评" of the change
//  source dialog.
//
//  Upstream:
//  app/src/main/java/io/legado/app/help/config/SourceConfig.kt
//

import Foundation

/// The scores the user gave to the books of the sources — upstream
/// `SourceConfig`.
///
/// The upstream keeps them in a SharedPreferences file named
/// "SourceConfig": one entry per book (`origin_name_author`, the ABSOLUTE
/// score of the book) and one entry per source (the origin, the sum of the
/// scores of its books).
///
/// The port stores the same data as one JSON blob in the `caches` table
/// (upstream `CacheDao`); the deadline 0 means that it never expires.
public struct SourceConfig: Codable, Equatable, Sendable {

    /// The key of the cached JSON — upstream the SharedPreferences name.
    public static let cacheKey = "sourceConfig"

    /// The absolute score of the books — the key is
    /// `origin_name_author`.
    public var bookScores: [String: Int]

    /// The summed score of the sources — the key is the origin.
    public var sourceScores: [String: Int]

    public init(bookScores: [String: Int] = [:], sourceScores: [String: Int] = [:]) {
        self.bookScores = bookScores
        self.sourceScores = sourceScores
    }

    // MARK: - The keys

    /// The key of the score of a book — upstream
    /// `"${origin}_${name}_${author}"`.
    public static func bookKey(origin: String, name: String, author: String) -> String {
        "\(origin)_\(name)_\(author)"
    }

    // MARK: - The scores

    /// The score of a book — upstream `SourceConfig.getBookScore`.
    public func bookScore(origin: String, name: String, author: String) -> Int {
        bookScores[Self.bookKey(origin: origin, name: name, author: author)] ?? 0
    }

    /// The score of a book by its key — upstream `SourceConfig.getBookScore`.
    public func bookScore(key: String) -> Int {
        bookScores[key] ?? 0
    }

    /// The summed score of a source — upstream `SourceConfig.getSourceScore`.
    public func sourceScore(origin: String) -> Int {
        sourceScores[origin] ?? 0
    }

    /// Sets the score of a book — upstream `SourceConfig.setBookScore`.
    ///
    /// The upstream stores the ABSOLUTE score of the book and adds the
    /// DELTA to the total of the source: clicking 好评 twice resets the score
    /// to 0 and the total of the source is restored.
    public mutating func setBookScore(origin: String, name: String, author: String, score: Int) {
        setBookScore(key: Self.bookKey(origin: origin, name: name, author: author), origin: origin, score: score)
    }

    /// Sets the score of a book by its key — the generic form.
    public mutating func setBookScore(key: String, origin: String, score: Int) {
        let previous = bookScores[key] ?? 0
        var delta = score
        if previous != 0 {
            delta = score - previous
        }
        sourceScores[origin] = (sourceScores[origin] ?? 0) + delta
        bookScores[key] = score
    }

    /// Removes the scores of a source — upstream `SourceConfig.removeSource`.
    ///
    /// The upstream removes every key that starts with the origin (the
    /// source's total and the books whose key starts with it).
    public mutating func removeSource(origin: String) {
        sourceScores.removeValue(forKey: origin)
        for key in bookScores.keys where key.hasPrefix(origin) {
            bookScores.removeValue(forKey: key)
        }
    }

    // MARK: - The persistence

    /// The JSON of the configuration — the value of the cached entry.
    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Parses the JSON of the configuration — a broken JSON gives the empty
    /// configuration.
    public static func parse(_ json: String) -> SourceConfig {
        guard let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(SourceConfig.self, from: data) else {
            return SourceConfig()
        }
        return config
    }

    /// Reads the configuration from the store — upstream
    /// `SourceConfig`'s SharedPreferences.
    public static func load(store: LegadoStore) -> SourceConfig {
        // `try?` flattens the optional result of `cache(_:now:)` into one
        // optional — a missing entry gives nil.
        guard let json = try? store.cache(cacheKey, now: 0) else {
            return SourceConfig()
        }
        return parse(json)
    }

    /// Writes the configuration into the store.
    public static func save(_ config: SourceConfig, store: LegadoStore) {
        try? store.putCache(cacheKey, value: config.jsonString, deadline: 0)
    }
}
