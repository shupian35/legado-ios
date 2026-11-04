//
//  SourceManagementTests.swift
//  LegadoCoreTests
//
//  The ordering and the selection of the book sources.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceAdapter.kt
//

import XCTest
@testable import LegadoCore

final class SourceManagementTests: XCTestCase {

    private func makeSources(_ count: Int) -> [BookSource] {
        (0..<count).map { index in
            BookSource(
                bookSourceUrl: "https://example.com/\(index)",
                bookSourceName: "源\(index)",
                customOrder: Int64(index)
            )
        }
    }

    // MARK: - The ordering

    func testSwappingTwoSourcesExchangesTheirOrder() {
        let sources = makeSources(3)
        let (first, second) = SourceOrdering.swap(sources[0], sources[2])
        XCTAssertEqual(first.customOrder, 2)
        XCTAssertEqual(second.customOrder, 0)
        // The sources themselves are untouched — Swift copies the structs.
        XCTAssertEqual(sources[0].customOrder, 0)
        XCTAssertEqual(sources[2].customOrder, 2)
    }

    func testRenumberingNumbersTheSourcesByTheirPosition() {
        let sources = makeSources(3)
        let numbered = SourceOrdering.renumber(sources, ascending: true)
        XCTAssertEqual(numbered.map(\.customOrder), [0, 1, 2])
        let descending = SourceOrdering.renumber(sources, ascending: false)
        XCTAssertEqual(descending.map(\.customOrder), [0, -1, -2])
    }

    func testTheOrderCollisionIsDetected() {
        let sources = makeSources(2)
        XCTAssertFalse(SourceOrdering.hasOrderCollision(sources))
        var first = sources[0]
        first.customOrder = 7
        var second = sources[1]
        second.customOrder = 7
        XCTAssertTrue(SourceOrdering.hasOrderCollision([first, second]))
    }

    // MARK: - The selection

    func testTheIntervalSelectionCoversTheWholeRange() {
        let sources = makeSources(5)
        let selected = SourceSelection.interval(
            selected: [sources[1].bookSourceUrl, sources[3].bookSourceUrl],
            in: sources
        )
        // Upstream `BookSourceAdapter.checkSelectedInterval` — the range runs
        // from the first selected row to the last one.
        XCTAssertEqual(selected.count, 3)
        XCTAssertFalse(selected.contains(sources[0].bookSourceUrl))
        XCTAssertTrue(selected.contains(sources[1].bookSourceUrl))
        XCTAssertTrue(selected.contains(sources[2].bookSourceUrl))
        XCTAssertTrue(selected.contains(sources[3].bookSourceUrl))
        XCTAssertFalse(selected.contains(sources[4].bookSourceUrl))
    }

    func testTheIntervalSelectionKeepsTheSelectionWhenItIsEmpty() {
        let sources = makeSources(3)
        let selected = SourceSelection.interval(selected: [], in: sources)
        XCTAssertTrue(selected.isEmpty)
    }

    func testTheInvertedSelectionAddsTheMissingSources() {
        let sources = makeSources(3)
        let selected = SourceSelection.inverted(
            selected: [sources[0].bookSourceUrl],
            in: sources
        )
        XCTAssertEqual(selected.count, 3)
    }

    func testSelectingEverySource() {
        let sources = makeSources(4)
        let selected = SourceSelection.all(in: sources)
        XCTAssertEqual(selected.count, 4)
    }
}
