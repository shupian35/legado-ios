//
//  TextPageFactory.swift
//  LegadoCore
//
//  The page cursor of the reader: it knows the current page and the pages
//  around it, and it moves between them.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextPageFactory.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/api/PageFactory.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/api/DataSource.kt
//

import Foundation

/// The data the page cursor works on — upstream `DataSource`.
public protocol ReaderDataSource: AnyObject {
    /// The index of the current page inside the current chapter.
    var pageIndex: Int { get set }
    /// The chapter that is being read.
    var currentChapter: TextChapter? { get }
    /// The next chapter, when it is already loaded.
    var nextChapter: TextChapter? { get }
    /// The previous chapter, when it is already loaded.
    var prevChapter: TextChapter? { get }

    /// Whether a next chapter exists.
    func hasNextChapter() -> Bool
    /// Whether a previous chapter exists.
    func hasPrevChapter() -> Bool
    /// Moves to the next chapter — returns false when there is none.
    @discardableResult func moveToNextChapter() -> Bool
    /// Moves to the previous chapter — returns false when there is none.
    @discardableResult func moveToPrevChapter() -> Bool
}

/// The page cursor — upstream `TextPageFactory`.
public final class TextPageFactory {
    private let dataSource: ReaderDataSource

    public init(dataSource: ReaderDataSource) {
        self.dataSource = dataSource
    }

    public var pageIndex: Int {
        get { dataSource.pageIndex }
        set { dataSource.pageIndex = newValue }
    }

    /// Whether there is a previous page.
    public var hasPrev: Bool {
        dataSource.hasPrevChapter() || pageIndex > 0
    }

    /// Whether there is a next page.
    public var hasNext: Bool {
        dataSource.hasNextChapter()
            || (dataSource.currentChapter?.isLastIndex(pageIndex) != true)
    }

    /// Whether there is a page after the next one.
    public var hasNextPlus: Bool {
        dataSource.hasNextChapter() || pageIndex < (dataSource.currentChapter?.pageSize ?? 1) - 2
    }

    /// Moves to the first page of the current chapter.
    public func moveToFirst() {
        dataSource.pageIndex = 0
    }

    /// Moves to the last page of the current chapter.
    public func moveToLast() {
        guard let chapter = dataSource.currentChapter else {
            dataSource.pageIndex = 0
            return
        }
        dataSource.pageIndex = chapter.pageSize == 0 ? 0 : chapter.pageSize - 1
    }

    /// Moves to the next page — returns false when there is none.
    @discardableResult
    public func moveToNext() -> Bool {
        guard hasNext else { return false }
        let index = pageIndex
        if dataSource.currentChapter == nil || dataSource.currentChapter?.isLastIndex(index) == true {
            guard dataSource.moveToNextChapter() else { return false }
        } else {
            if index < 0 || dataSource.currentChapter?.isLastIndexCurrent(index) == true {
                return false
            }
            dataSource.pageIndex = index + 1
        }
        return true
    }

    /// Moves to the previous page — returns false when there is none.
    @discardableResult
    public func moveToPrev() -> Bool {
        guard hasPrev else { return false }
        if pageIndex <= 0 {
            if dataSource.currentChapter == nil && dataSource.prevChapter == nil {
                return false
            }
            if let previous = dataSource.prevChapter, !previous.isCompleted {
                return false
            }
            guard dataSource.moveToPrevChapter() else { return false }
        } else {
            guard dataSource.currentChapter != nil else { return false }
            dataSource.pageIndex = pageIndex - 1
        }
        return true
    }

    /// The current page.
    public var currentPage: TextPage {
        guard let chapter = dataSource.currentChapter else { return TextPage() }
        return chapter.page(at: pageIndex) ?? TextPage()
    }

    /// The next page.
    public var nextPage: TextPage {
        guard let chapter = dataSource.currentChapter else { return TextPage() }
        let index = pageIndex
        if index < chapter.pageSize - 1 {
            return chapter.page(at: index + 1)?.removePageAloudSpan() ?? TextPage()
        }
        if !chapter.isCompleted { return TextPage() }
        guard let next = dataSource.nextChapter else { return TextPage() }
        return next.page(at: 0)?.removePageAloudSpan() ?? TextPage()
    }

    /// The previous page.
    public var prevPage: TextPage {
        guard let chapter = dataSource.currentChapter else { return TextPage() }
        let index = pageIndex
        if index > 0 {
            return chapter.page(at: index - 1)?.removePageAloudSpan() ?? TextPage()
        }
        if !chapter.isCompleted { return TextPage() }
        guard let previous = dataSource.prevChapter else { return TextPage() }
        return previous.lastPage?.removePageAloudSpan() ?? TextPage()
    }

    /// The page after the next one.
    public var nextPlusPage: TextPage {
        guard let chapter = dataSource.currentChapter else { return TextPage() }
        let index = pageIndex
        if index < chapter.pageSize - 2 {
            return chapter.page(at: index + 2)?.removePageAloudSpan() ?? TextPage()
        }
        if !chapter.isCompleted { return TextPage() }
        guard let next = dataSource.nextChapter else { return TextPage() }
        if index < chapter.pageSize - 1 {
            return next.page(at: 0)?.removePageAloudSpan() ?? TextPage()
        }
        return next.page(at: 1)?.removePageAloudSpan() ?? TextPage()
    }
}
