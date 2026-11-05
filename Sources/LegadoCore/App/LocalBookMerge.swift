//
//  LocalBookMerge.swift
//  LegadoCore
//
//  The merge of the information of a book of a download service into the
//  imported local book — the port of
//  app/src/main/java/io/legado/app/model/localBook/LocalBook.kt:466
//  (`fun mergeBook(localBook: Book, onLineBook: Book?): Book`).
//
//  Upstream the comment reads "文件类书源 合并在线书籍信息 在线 > 本地"
//  (a source of the file type merges the information of the online book,
//  the online book wins over the local one).
//

import Foundation

/// The merge of the information of an online book into the local one.
public enum LocalBookMerge {

    /// Merges the information of the online book into the local book.
    ///
    /// The name and the author of the online book win when they are not
    /// blank; the cover always wins; the introduction of the online book
    /// wins when it is not blank.
    ///
    /// - Parameters:
    ///   - local: the imported local book.
    ///   - online: the book of the source — `nil` leaves the local book
    ///     untouched (the upstream returns the local book unchanged).
    /// - Returns: the merged book.
    public static func merge(local: Book, online: Book?) -> Book {
        guard let online else { return local }
        var merged = local
        if !online.name.isEmpty {
            merged.name = online.name
        }
        if !online.author.isEmpty {
            merged.author = online.author
        }
        merged.coverUrl = online.coverUrl
        if let intro = online.intro, !intro.isEmpty {
            merged.intro = intro
        }
        return merged
    }
}
