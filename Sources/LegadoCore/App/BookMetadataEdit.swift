//
//  BookMetadataEdit.swift
//  LegadoCore
//
//  The editor of the book metadata — upstream
//  `ui/book/info/edit/BookInfoEditActivity`.
//
//  The upstream edits the name, the author, the book type, the cover and the
//  introduction:
//
//      val local = if (book.isLocal) BookType.local else 0
//      val bookType = when (spType.selectedItemPosition) {
//          2 -> BookType.image or local
//          1 -> BookType.audio or local
//          else -> BookType.text or local
//      }
//      book.removeType(BookType.local, BookType.image, BookType.audio, BookType.text)
//      book.addType(bookType)
//
//  and the cover:
//
//      book.customCoverUrl = if (customCoverUrl == book.coverUrl) null else customCoverUrl
//      book.customIntro = if (customIntro == book.intro) null else customIntro
//

import Foundation

/// The kind of a book — upstream `@array/book_type` (the spinner of the book
/// type).
public enum BookKind: Int, CaseIterable, Identifiable, Sendable {
    /// 0 — a text book.
    case text = 0
    /// 1 — an audio book.
    case audio = 1
    /// 2 — an image (comic) book.
    case image = 2

    public var id: Int { rawValue }

    /// The title of the entry — upstream `R.array.book_type`.
    public var displayName: String {
        switch self {
        case .text: return "文本"
        case .audio: return "音频"
        case .image: return "图片"
        }
    }

    /// The type bit — upstream `BookType.text` / `audio` / `image`.
    public var typeBit: Int64 {
        switch self {
        case .text: return BookType.text
        case .audio: return BookType.audio
        case .image: return BookType.image
        }
    }
}

/// The logic of the book metadata editor.
public enum BookMetadataEdit {

    /// The kind of the book — upstream `BookInfoEditActivity.upView`:
    /// the image book is 2, the audio book is 1 and everything else is 0.
    public static func kind(of book: Book) -> BookKind {
        if book.isImage { return .image }
        if book.isAudio { return .audio }
        return .text
    }

    /// The type of the book after the kind was chosen — upstream
    /// `BookInfoEditActivity.saveData`.
    ///
    /// The local bit of a local book is kept; the four content bits are
    /// replaced.
    public static func type(_ kind: BookKind, book: Book) -> Int64 {
        let local = book.isLocal ? BookType.local : 0
        let bookType = kind.typeBit | local
        var type = book.type
        // Upstream `removeType(BookType.local, BookType.image, BookType.audio,
        // BookType.text)` — `type = type and it.inv()`.
        for bit in [BookType.local, BookType.image, BookType.audio, BookType.text] {
            type = type & ~bit
        }
        // Upstream `addType(bookType)` — `type = type or it`.
        return type | bookType
    }

    /// The custom cover of the book — upstream
    /// `book.customCoverUrl = if (customCoverUrl == book.coverUrl) null else customCoverUrl`.
    public static func customCoverUrl(_ url: String, book: Book) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed == book.coverUrl ? nil : trimmed
    }

    /// The custom introduction of the book — upstream
    /// `book.customIntro = if (customIntro == book.intro) null else customIntro`.
    public static func customIntro(_ intro: String, book: Book) -> String? {
        let trimmed = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed == book.intro ? nil : trimmed
    }

    /// The cover that is shown — upstream `Book.getDisplayCover()`.
    public static func displayCover(_ book: Book) -> String {
        if let custom = book.customCoverUrl, !custom.isEmpty { return custom }
        return book.coverUrl ?? ""
    }
}
