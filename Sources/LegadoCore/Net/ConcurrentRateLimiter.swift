//
//  ConcurrentRateLimiter.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/help/ConcurrentRateLimiter.kt.
//

import Foundation

/// The error thrown when a source is accessed faster than its 并发率 allows.
public struct ConcurrentError: Error, Equatable {
    public let message: String
    public let waitTime: Int

    public init(message: String, waitTime: Int) {
        self.message = message
        self.waitTime = waitTime
    }
}

/// The rate record of one source.
public final class ConcurrentRecord: @unchecked Sendable {
    /// `true` when the rate is expressed as "count/milliseconds".
    public let isConcurrent: Bool
    /// The time of the last access.
    public var time: Int64
    /// The number of in-flight accesses.
    public var frequency: Int
    private let lock = NSLock()

    init(isConcurrent: Bool, time: Int64, frequency: Int) {
        self.isConcurrent = isConcurrent
        self.time = time
        self.frequency = frequency
    }

    /// Run `body` while holding the record's lock.
    func synchronized<T>(_ body: (ConcurrentRecord) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

/// Limits how fast a book source may be accessed.
///
/// The upstream implementation keeps one record per source key in a static map;
/// the port keeps the same shared map.
public final class ConcurrentRateLimiter: @unchecked Sendable {
    /// The shared record map.
    private final class RecordMap: @unchecked Sendable {
        private var storage: [String: ConcurrentRecord] = [:]
        private let lock = NSLock()

        func record(for key: String) -> ConcurrentRecord? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        func insert(key: String, record: ConcurrentRecord) -> ConcurrentRecord {
            lock.lock()
            defer { lock.unlock() }
            if let existing = storage[key] { return existing }
            storage[key] = record
            return record
        }
    }

    private static let records = RecordMap()

    /// The key of the source the limiter belongs to.
    public let key: String?
    /// The configured rate: `"1000"` (ms between requests) or `"20/60000"`.
    public let concurrentRate: String?

    public init(key: String?, concurrentRate: String?) {
        self.key = key
        self.concurrentRate = concurrentRate
    }

    /// Acquire the permission to access the source, waiting when needed.
    public func concurrentRecord() async -> ConcurrentRecord? {
        while true {
            do {
                return try fetchStart()
            } catch let error as ConcurrentError {
                let nanoseconds = UInt64(max(0, error.waitTime) * 1_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return nil
            }
        }
    }

    /// Acquire the permission to access the source, blocking the calling thread.
    public func concurrentRecordBlocking() -> ConcurrentRecord? {
        while true {
            do {
                return try fetchStart()
            } catch let error as ConcurrentError {
                Thread.sleep(forTimeInterval: Double(max(0, error.waitTime)) / 1000)
            } catch {
                return nil
            }
        }
    }

    /// Run `body` while respecting the rate limit.
    public func withLimit<T>(_ body: () async throws -> T) async rethrows -> T {
        let record = await concurrentRecord()
        defer { fetchEnd(record) }
        return try await body()
    }

    /// Run `body` while respecting the rate limit (blocking).
    public func withLimitBlocking<T>(_ body: () throws -> T) rethrows -> T {
        let record = concurrentRecordBlocking()
        defer { fetchEnd(record) }
        return try body()
    }

    // MARK: - Implementation

    /// Start an access — upstream `fetchStart`.
    public func fetchStart() throws -> ConcurrentRecord? {
        guard let key else { return nil }
        guard let concurrentRate, !concurrentRate.isEmpty, concurrentRate != "0" else { return nil }
        let rateIndex = concurrentRate.firstIndex(of: "/")
        // Upstream: `ConcurrentRecord(rateIndex > 0, ...)`.
        let isConcurrentRate = rateIndex.map { $0 > concurrentRate.startIndex } ?? false
        guard let existing = ConcurrentRateLimiter.records.record(for: key) else {
            let record = ConcurrentRecord(
                isConcurrent: isConcurrentRate,
                time: Self.nowMillis(),
                frequency: 1
            )
            return ConcurrentRateLimiter.records.insert(key: key, record: record)
        }
        let waitTime = existing.synchronized { record -> Int in
            if !record.isConcurrent {
                // The rate is a delay between two requests.
                let delay = Int64(concurrentRate) ?? 0
                if record.frequency > 0 {
                    return Int(delay)
                }
                let nextTime = record.time + delay
                let now = Self.nowMillis()
                if now >= nextTime {
                    record.time = now
                    record.frequency = 1
                    return 0
                }
                return Int(nextTime - now)
            } else {
                // The rate is "count/milliseconds".
                let millisText = String(concurrentRate[concurrentRate.index(after: rateIndex!)...])
                let millis = Int64(millisText) ?? 0
                let nextTime = record.time + millis
                let now = Self.nowMillis()
                if now >= nextTime {
                    record.time = now
                    record.frequency = 1
                    return 0
                }
                let countText = String(concurrentRate[concurrentRate.startIndex..<rateIndex!])
                let count = Int(countText) ?? 0
                if record.frequency > count {
                    return Int(nextTime - now)
                } else {
                    record.frequency += 1
                    return 0
                }
            }
        }
        if waitTime > 0 {
            throw ConcurrentError(
                message: "根据并发率还需等待\(waitTime)毫秒才可以访问",
                waitTime: waitTime
            )
        }
        return existing
    }

    /// Release the access — upstream `fetchEnd`.
    public func fetchEnd(_ record: ConcurrentRecord?) {
        guard let record, !record.isConcurrent else { return }
        record.synchronized { record in
            record.frequency -= 1
        }
    }

    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
