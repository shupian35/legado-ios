//
//  ReadRecords.swift
//  LegadoCore
//
//  The reading records — the screen `ui/about/ReadRecordActivity.kt`.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/about/ReadRecordActivity.kt
//  app/src/main/java/io/legado/app/data/dao/ReadRecordDao.kt
//  app/src/main/java/io/legado/app/data/entities/ReadRecordShow.kt
//

import Foundation

/// A row of the reading records — upstream `ReadRecordShow`.
///
/// The upstream groups the records by the name of the book: the reading time
/// is summed up and the last reading is the newest one.
public struct ReadRecordShow: Equatable, Identifiable, Sendable {

    /// The name of the book.
    public var bookName: String
    /// The summed reading time, in milliseconds.
    public var readTime: Int64
    /// The newest reading, in milliseconds.
    public var lastRead: Int64

    public var id: String { bookName }

    public init(bookName: String, readTime: Int64 = 0, lastRead: Int64 = 0) {
        self.bookName = bookName
        self.readTime = readTime
        self.lastRead = lastRead
    }

    /// The reading time in a human readable form — upstream
    /// `ReadRecordActivity.formatDuring` (L219-233).
    ///
    /// The days, the hours, the minutes and the seconds that are not zero; the
    /// empty result is "0秒".
    public var readDurationText: String {
        let total = max(0, readTime)
        let days = total / (1000 * 60 * 60 * 24)
        let hours = total % (1000 * 60 * 60 * 24) / (1000 * 60 * 60)
        let minutes = total % (1000 * 60 * 60) / (1000 * 60)
        let seconds = total % (1000 * 60) / 1000
        var text = ""
        if days > 0 { text += "\(days)天" }
        if hours > 0 { text += "\(hours)小时" }
        if minutes > 0 { text += "\(minutes)分钟" }
        if seconds > 0 { text += "\(seconds)秒" }
        return text.isEmpty ? "0秒" : text
    }

    /// The last reading as a date — upstream `ReadRecordActivity`'s
    /// `dateFormat` ("yyyy-MM-dd").
    public var lastReadText: String {
        guard lastRead > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(lastRead) / 1000)
        return ReadRecordShow.dateFormatter.string(from: date)
    }

    /// The formatter of the dates — upstream `SimpleDateFormat("yyyy-MM-dd")`.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        return formatter
    }()
}

/// The sorting of the reading records — upstream `ReadRecordActivity.sortMode`.
///
/// The mode is stored in the local configuration under the key
/// "readRecordSort" (`LocalConfig.getInt("readRecordSort")`).
public enum ReadRecordSort: Int, CaseIterable, Identifiable, Sendable {

    /// 0 — by the name of the book (the upstream's `cnCompare`).
    case name = 0
    /// 1 — by the reading time, the longest first.
    case readTime = 1
    /// 2 — by the last reading, the newest first.
    case lastRead = 2

    public var id: Int { rawValue }

    /// The title of the sort — upstream `res/menu/book_read_record.xml`.
    public var displayName: String {
        switch self {
        case .name: return "按名称"
        case .readTime: return "按阅读时长"
        case .lastRead: return "按阅读时间"
        }
    }
}

/// The model of the reading records — upstream `ReadRecordDao` +
/// `ReadRecordActivity.initData`.
public struct ReadRecordModel {

    private let store: LegadoStore

    public init(store: LegadoStore) {
        self.store = store
    }

    /// The records of the screen — upstream `ReadRecordDao.search(searchKey)`.
    ///
    /// The records are grouped by the name of the book; the search matches the
    /// name with a `LIKE` (upstream `bookName like '%' || :searchKey || '%'`).
    public func records(searchKey: String = "", sort: ReadRecordSort = .name) throws -> [ReadRecordShow] {
        var rows: [ReadRecord]
        if searchKey.isEmpty {
            rows = try store.allReadRecords()
        } else {
            rows = try store.readRecords(matching: searchKey)
        }
        // Upstream `group by bookName` — the reading time is summed up and the
        // last reading is the newest one.
        var order: [String] = []
        var grouped: [String: ReadRecordShow] = [:]
        for record in rows {
            if var existing = grouped[record.bookName] {
                existing.readTime += record.readTime
                existing.lastRead = max(existing.lastRead, record.lastRead)
                grouped[record.bookName] = existing
            } else {
                grouped[record.bookName] = ReadRecordShow(
                    bookName: record.bookName,
                    readTime: record.readTime,
                    lastRead: record.lastRead
                )
                order.append(record.bookName)
            }
        }
        let shows = order.compactMap { grouped[$0] }
        return sorted(shows, by: sort)
    }

    /// Sorts the records — upstream `ReadRecordActivity.initData`.
    private func sorted(_ records: [ReadRecordShow], by mode: ReadRecordSort) -> [ReadRecordShow] {
        switch mode {
        case .name:
            // Upstream `sortedWith { o1, o2 -> o1.bookName.cnCompare(o2.bookName) }`.
            return records.sorted { TextComparison.isOrderedBefore($0.bookName, $1.bookName) }
        case .readTime:
            return records.sorted { $0.readTime > $1.readTime }
        case .lastRead:
            return records.sorted { $0.lastRead > $1.lastRead }
        }
    }

    /// The total reading time — upstream `ReadRecordDao.allTime`.
    public func totalTime() throws -> Int64 {
        try store.allReadRecords().reduce(0) { $0 + $1.readTime }
    }

    /// Deletes the records of a book — upstream `ReadRecordDao.deleteByName`.
    public func delete(bookName: String) throws {
        try store.deleteReadRecords(bookName: bookName)
    }

    /// Deletes every record — upstream `ReadRecordDao.clear`.
    public func clear() throws {
        try store.clearReadRecords()
    }
}
