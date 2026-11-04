//
//  TextComparisonTests.swift
//  LegadoCoreTests
//
//  The pinyin aware comparison of the shelf — upstream `String.cnCompare`
//  (`app/src/main/java/io/legado/app/utils/StringExtensions.kt:97-103`):
//
//  ```kotlin
//  fun String.cnCompare(other: String): Int {
//      return Collator.getInstance(ULocale.SIMPLIFIED_CHINESE).compare(this, other)
//  }
//  ```
//

import XCTest
@testable import LegadoCore

final class TextComparisonTests: XCTestCase {

    /// The Chinese titles are ordered by their pronunciation, not by their
    /// code points.
    func testTheChineseTitlesAreOrderedByTheirPronunciation() {
        let titles = ["张三", "李四", "阿凡提", "赵六", "曹操", "白起"]
        let sorted = titles.sorted(by: TextComparison.isOrderedBefore)
        XCTAssertEqual(sorted, ["阿凡提", "白起", "曹操", "李四", "张三", "赵六"])
    }

    /// The code point order would be a different one — the test documents
    /// that the comparison is really the pinyin one.
    func testThePinyinOrderIsNotTheCodePointOrder() {
        let titles = ["张三", "李四", "阿凡提", "赵六", "曹操", "白起"]
        XCTAssertNotEqual(titles.sorted(), titles.sorted(by: TextComparison.isOrderedBefore))
    }

    /// The collation of the upstream has the tertiary strength — the case only
    /// decides when the words are the same.
    func testTheCaseOnlyDecidesWhenTheWordsAreTheSame() {
        XCTAssertTrue(TextComparison.isOrderedBefore("apple", "Apple"))
        XCTAssertFalse(TextComparison.isOrderedBefore("Apple", "apple"))
        XCTAssertTrue(TextComparison.isOrderedBefore("apple", "Banana"))
        XCTAssertTrue(TextComparison.isOrderedBefore("Apple", "banana"))
        XCTAssertFalse(TextComparison.isOrderedBefore("Banana", "apple"))
    }

    /// A string is not before itself.
    func testAStringIsNotBeforeItself() {
        XCTAssertFalse(TextComparison.isOrderedBefore("同名", "同名"))
    }

    /// The sort of the shelf by name uses the pinyin order.
    func testTheShelfSortByNameUsesThePinyinOrder() {
        let books = [
            Book(bookUrl: "a", name: "张三"),
            Book(bookUrl: "b", name: "阿凡提"),
            Book(bookUrl: "c", name: "曹操")
        ]
        let sorted = BookshelfSort.byName.sort(books)
        XCTAssertEqual(sorted.map(\.bookUrl), ["b", "c", "a"])
    }

    /// The sort of the shelf by author uses the pinyin order.
    func testTheShelfSortByAuthorUsesThePinyinOrder() {
        let books = [
            Book(bookUrl: "a", name: "一", author: "张三"),
            Book(bookUrl: "b", name: "二", author: "阿凡提"),
            Book(bookUrl: "c", name: "三", author: "曹操")
        ]
        let sorted = BookshelfSort.byAuthor.sort(books)
        XCTAssertEqual(sorted.map(\.bookUrl), ["b", "c", "a"])
    }
}
