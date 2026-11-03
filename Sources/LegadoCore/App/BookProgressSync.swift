//
//  BookProgressSync.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/ReadBookViewModel.kt:240-262
//  (syncBookProgress) and app/src/main/java/io/legado/app/model/ReadBook.kt:237-247
//  (uploadProgress).
//
//  The reading progress is exchanged with the WebDAV server — one JSON file
//  per book in `bookProgress/`. The reader offers two actions:
//
//  * 获取进度 — fetch the remote progress and apply it when it is further
//    into the book than the local one; when the remote one is older the user
//    is asked whether to overwrite the local progress.
//  * 覆盖进度 — upload the local progress, overwriting the remote one.
//
//

import Foundation

/// What the reader does with the progress it fetched from the server.
public enum BookProgressSyncOutcome: Equatable, Sendable {
    /// The remote progress and the local one are at the same place — the
    /// upstream returns without a message.
    case same
    /// The remote progress is further into the book — it is applied.
    case remoteNewer(BookProgress)
    /// The remote progress is older — the upstream asks the user whether the
    /// local progress should be overwritten.
    case remoteOlder(BookProgress)
    /// The remote progress points past the end of the book — it is ignored
    /// (the upstream checks `durChapterIndex < simulatedTotalChapterNum`).
    case beyondTheBook(BookProgress)
}

public enum BookProgressSync {

    /// Decides what to do with the progress that came from the server — the
    /// port of `ReadBookViewModel.syncBookProgress`.
    ///
    /// - Parameters:
    ///   - remote: the progress that was fetched from the server.
    ///   - local: the progress of this device.
    ///   - totalChapters: the number of chapters of the book (the upstream
    ///     uses `simulatedTotalChapterNum`, so the simulation is honoured).
    public static func resolve(
        remote: BookProgress,
        local: BookProgress,
        totalChapters: Int
    ) -> BookProgressSyncOutcome {
        if remote.durChapterIndex == local.durChapterIndex
            && remote.durChapterPos == local.durChapterPos {
            return .same
        }
        if remote.durChapterIndex < local.durChapterIndex
            || (remote.durChapterIndex == local.durChapterIndex
                && remote.durChapterPos < local.durChapterPos) {
            return .remoteOlder(remote)
        }
        if remote.durChapterIndex < totalChapters {
            return .remoteNewer(remote)
        }
        return .beyondTheBook(remote)
    }
}
