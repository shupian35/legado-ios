//
//  SearchHistory.swift
//  LegadoCore
//
//  The history of the searches.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/search/SearchViewModel.kt
//    (saveSearchKey, clearHistory, deleteHistory)
//  app/src/main/java/io/legado/app/data/dao/SearchKeywordDao.kt
//    (flowByTime, getByKey, insert, delete, deleteAll)
//

import Foundation

/// The history of the searches — upstream `SearchViewModel` and
/// `SearchKeywordDao`.
///
/// The upstream keeps the keywords in the `searchKeyword` table with the
/// number of times a keyword was used and the time of its last use. The port
/// reads and writes the same table through `LegadoStore`.
///
/// The upstream can also delete a keyword and clear the whole history
/// (`SearchKeywordDao.delete` / `deleteAll`); the port's store does not expose
/// a delete for this table yet, so the deleted words are remembered in the
/// preferences and hidden from the history. The store should grow a
/// `deleteSearchKeywords()` / `deleteSearchKeyword(word:)` to replace the
/// workaround.
public enum SearchHistory {

    /// The preference that holds the words that were deleted from the
    /// history — the workaround for the missing delete in the store.
    static let removedKey = "searchHistoryRemoved"

    /// The keywords of the history, the most recent first — upstream
    /// `SearchKeywordDao.flowByTime`.
    public static func keywords(store: LegadoStore, settings: AppSettings) -> [SearchKeyword] {
        let removed = removedWords(settings: settings)
        let all = (try? store.allSearchKeywords()) ?? []
        return all
            .filter { !removed.contains($0.word) }
            .sorted {
                if $0.lastUseTime != $1.lastUseTime { return $0.lastUseTime > $1.lastUseTime }
                if $0.usage != $1.usage { return $0.usage > $1.usage }
                return $0.word < $1.word
            }
    }

    /// Saves a keyword in the history — upstream
    /// `SearchViewModel.saveSearchKey`.
    ///
    /// A keyword that is already known gets one more use and the current
    /// time, a new keyword is inserted with one use.
    public static func save(_ word: String, store: LegadoStore, settings: AppSettings) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A keyword that was deleted comes back.
        setRemovedWords(removedWords(settings: settings).filter { $0 != trimmed }, settings: settings)
        let all = (try? store.allSearchKeywords()) ?? []
        if let existing = all.first(where: { $0.word == trimmed }) {
            var keyword = existing
            keyword.usage += 1
            keyword.lastUseTime = Int64(Date().timeIntervalSince1970 * 1000)
            try? store.insert(keyword)
        } else {
            // Upstream `SearchKeyword(key, 1)`.
            try? store.insert(SearchKeyword(word: trimmed, usage: 1, lastUseTime: 0))
        }
    }

    /// Deletes a keyword of the history — upstream
    /// `SearchViewModel.deleteHistory`.
    public static func delete(_ word: String, settings: AppSettings) {
        var removed = removedWords(settings: settings)
        if !removed.contains(word) { removed.append(word) }
        setRemovedWords(removed, settings: settings)
    }

    /// Clears the history — upstream `SearchViewModel.clearHistory`.
    public static func clear(store: LegadoStore, settings: AppSettings) {
        let words = ((try? store.allSearchKeywords()) ?? []).map(\.word)
        setRemovedWords(removedWords(settings: settings) + words.filter { word in
            !removedWords(settings: settings).contains(word)
        }, settings: settings)
    }

    // MARK: - The deleted words

    private static func removedWords(settings: AppSettings) -> [String] {
        guard let text = settings.settingsStore.string(forKey: removedKey), !text.isEmpty else {
            return []
        }
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }

    private static func setRemovedWords(_ words: [String], settings: AppSettings) {
        guard !words.isEmpty else {
            settings.settingsStore.removeValue(forKey: removedKey)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: words),
              let text = String(data: data, encoding: .utf8) else { return }
        settings.settingsStore.set(text, forKey: removedKey)
    }
}
