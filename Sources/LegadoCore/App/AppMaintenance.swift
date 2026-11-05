//
//  AppMaintenance.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/App.kt:93-126 (the startup block of
//  `Application.onCreate`) and
//  app/src/main/java/io/legado/app/help/DefaultData.kt:24-43 (`upVersion`).
//
//  The upstream runs, when the process starts:
//
//      DefaultData.upVersion()                       // the default data
//      appDb.cacheDao.clearDeadline(now)             // the expired caches
//      if (autoClearExpired) appDb.searchBookDao.clearExpired(now - 1 day)
//      RuleBigDataHelp.clearInvalid()                // the rule variables
//      BookHelp.clearInvalidCache()                  // the cache of the deleted books
//      Backup.clearCache()                           // the temporary backups
//      ReadBookConfig.clearBgAndCache()              // the reading backgrounds
//      ThemeConfig.clearBg()                         // the theme backgrounds
//      SourceHelp.adjustSortNumber()                 // the sort numbers
//      if (syncBookProgress) AppWebDav.downloadAllBookProgress()
//
//  The port runs the same steps. `RuleBigDataHelp` is not applicable — the
//  port keeps the rule variables in memory (see `RuleDataBox`) instead of in
//  the file system, so there is nothing to clean up.
//

import Foundation

/// The maintenance that runs when the application starts — upstream `App` and
/// `DefaultData`.
public enum AppMaintenance {

    // MARK: - The report

    /// What the cleanup did — the port shows it in the log of the app.
    public struct Report: Equatable, Sendable {
        /// The expired cache entries were removed — upstream
        /// `CacheDao.clearDeadline`.
        public var clearedCaches = false
        /// The expired search results were removed — upstream
        /// `SearchBookDao.clearExpired`.
        public var clearedSearchBooks = false
        /// The cache folders of the books that are no longer on the shelf were
        /// removed — upstream `BookHelp.clearInvalidCache`.
        public var clearedBookCaches = 0
        /// The sort numbers of the sources were renumbered — upstream
        /// `SourceHelp.adjustSortNumber`.
        public var adjustedSourceOrder = false
        /// The default data that was imported — upstream
        /// `DefaultData.upVersion`.
        public var importedDefaults: [String] = []
    }

    // MARK: - The startup cleanup

    /// Runs the cleanup of the expired data — upstream `App.kt:101-122`.
    ///
    /// - Parameters:
    ///   - store: the database.
    ///   - settings: the preferences (the `autoClearExpired` switch).
    ///   - cacheStorage: the chapter cache — the folders of the books that
    ///     are no longer in the database are deleted.
    ///   - now: the current time in milliseconds since the epoch.
    public static func cleanUp(
        store: LegadoStore,
        settings: AppSettings,
        cacheStorage: BookCacheStorage? = nil,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> Report {
        var report = Report()
        // The expired cache entries.
        try store.clearExpiredCaches(now: now)
        report.clearedCaches = true
        // The search results of the last day — only when the preference is on.
        // The upstream default of `PreferKey.autoClearExpired` is **true**.
        if settings.autoClearExpired {
            try store.clearExpiredSearchBooks(before: now - 86_400_000)
            report.clearedSearchBooks = true
        }
        // The cache of the books that were deleted.
        if let cacheStorage {
            report.clearedBookCaches = try clearInvalidBookCaches(
                store: store,
                cacheStorage: cacheStorage
            )
        }
        // The sort numbers of the sources.
        report.adjustedSourceOrder = try adjustSourceOrder(store: store)
        return report
    }

    // MARK: - The cache of the deleted books

    /// Deletes the cache folders of the books that are no longer in the
    /// database — upstream `BookHelp.clearInvalidCache`.
    ///
    /// The upstream walks the cache folder and deletes every folder whose name
    /// is not the folder of one of the books of the database.
    ///
    /// - Returns: the number of the folders that were deleted.
    @discardableResult
    public static func clearInvalidBookCaches(
        store: LegadoStore,
        cacheStorage: BookCacheStorage,
        fileManager: FileManager = .default
    ) throws -> Int {
        let books = try store.allBooks()
        let known = Set(books.map { BookCacheLayout.folderName(for: $0) })
        let root = cacheStorage.layout.root
        let folders = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var deleted = 0
        for folder in folders {
            let name = folder.lastPathComponent
            guard !known.contains(name) else { continue }
            try? fileManager.removeItem(at: folder)
            deleted += 1
        }
        return deleted
    }

    // MARK: - The sort numbers of the sources

    /// Renumbers the sources when their sort numbers went out of range or
    /// collide — upstream `SourceHelp.adjustSortNumber`.
    ///
    /// The upstream renumbers them from `0` when the biggest number is above
    /// `99999`, when the smallest is below `-99999` or when two sources share
    /// the same number.
    ///
    /// - Returns: whether the sources were renumbered.
    @discardableResult
    public static func adjustSourceOrder(store: LegadoStore) throws -> Bool {
        let sources = try store.allSources()
        guard !sources.isEmpty else { return false }
        let orders = sources.map(\.customOrder)
        let maximum = orders.max() ?? 0
        let minimum = orders.min() ?? 0
        let hasDuplicate = Set(orders).count != orders.count
        guard maximum > 99_999 || minimum < -99_999 || hasDuplicate else { return false }
        for (index, source) in sources.enumerated() {
            guard source.customOrder != Int64(index) else { continue }
            var updated = source
            updated.customOrder = Int64(index)
            try store.insert(updated)
        }
        return true
    }

    // MARK: - The reading progress

    /// Downloads the reading progress of the books from the WebDAV server —
    /// upstream `AppWebDav.downloadAllBookProgress`.
    ///
    /// The upstream walks the books of the shelf, finds the progress file of
    /// each of them and applies the remote progress when it is further into
    /// the book than the local one. A file that is older than the last
    /// synchronisation of the book is skipped.
    ///
    /// - Returns: the number of the books whose progress was updated.
    @discardableResult
    public static func downloadAllBookProgress(
        store: LegadoStore,
        service: WebDavService,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async throws -> Int {
        var byName: [String: WebDavFile] = [:]
        for file in try await service.progressFiles() {
            byName[file.name] = file
        }
        var updated = 0
        for book in try store.allBooks() {
            let fileName = BookProgress(book: book).fileName
            guard let file = byName[fileName] else { continue }
            // The local copy is at least as new as the remote one.
            if let modified = file.lastModified,
               Int64(modified.timeIntervalSince1970 * 1000) <= book.syncTime {
                continue
            }
            guard let progress = try? await service.downloadProgress(fileName: fileName) else { continue }
            guard progress.durChapterIndex > book.durChapterIndex
                || (progress.durChapterIndex == book.durChapterIndex
                    && progress.durChapterPos > book.durChapterPos) else { continue }
            var changed = book
            changed.durChapterIndex = Int64(progress.durChapterIndex)
            changed.durChapterPos = Int64(progress.durChapterPos)
            changed.durChapterTitle = progress.durChapterTitle
            changed.durChapterTime = progress.durChapterTime
            changed.syncTime = now
            try store.update(changed)
            updated += 1
        }
        return updated
    }

    // MARK: - The default data

    /// Imports the default data after an upgrade — upstream
    /// `DefaultData.upVersion`.
    ///
    /// The upstream imports the default HTTP TTS engines, the TXT table of
    /// contents rules, the RSS sources and the dictionary rules when the
    /// version of the app grew; every kind of data has its own version
    /// counter, so a data set that did not change is not imported again.
    ///
    /// - Parameters:
    ///   - store: the database.
    ///   - localConfig: the local configuration — it holds the version
    ///     counters.
    /// - Returns: the kinds of the data that were imported.
    @discardableResult
    public static func importDefaultsAfterUpgrade(
        store: LegadoStore,
        localConfig: LocalConfig
    ) throws -> [String] {
        var imported: [String] = []
        if localConfig.needsDefaultHttpTTS {
            try DefaultData.importDefaultHttpTTS(store: store)
            imported.append("httpTTS")
        }
        if localConfig.needsDefaultTxtTocRules {
            try DefaultData.importDefaultTocRules(store: store)
            imported.append("txtTocRule")
        }
        if localConfig.needsDefaultRssSources {
            try DefaultData.importDefaultRssSources(store: store)
            imported.append("rssSources")
        }
        if localConfig.needsDefaultDictRules {
            try DefaultData.importDefaultDictRules(store: store)
            imported.append("dictRules")
        }
        return imported
    }
}
