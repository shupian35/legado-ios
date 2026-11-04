import XCTest
@testable import LegadoCore

/// The tests of the reader batch — the page turn, the tip colours, the shelf
/// question and the read aloud of a selection.
final class ReaderBatchTests: XCTestCase {

    // MARK: - The read aloud of a selection

    /// The upstream's `contentSelectSpeakMod` decides what the 朗读 action of
    /// the selection menu does (`ReadBookActivity.kt:848-854`): 0 reads the
    /// selection, 1 reads from the selection to the end of the chapter.
    func testTheReadAloudModeDefaultsToTheSelection() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.contentSelectSpeakMod, 0)
    }

    func testTheReadAloudModeIsStored() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.contentSelectSpeakMod = 1
        XCTAssertEqual(settings.contentSelectSpeakMod, 1)
    }

    /// The key of the upstream is "contentReadAloudMod" — the constant name
    /// differs from the key (`PreferKey.kt:188`).
    func testTheReadAloudModeUsesTheUpstreamKey() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        settings.contentSelectSpeakMod = 1
        XCTAssertEqual(store.int(forKey: "contentReadAloudMod"), 1)
    }

    // MARK: - The position of a selection

    /// The chapter position of a character offset of the page — the port adds
    /// the start of the page to the offset inside the page.
    func testTheChapterPositionOfAPageOffset() {
        let page = TextPage()
        page.text = "abcdefghij"
        page.chapterIndex = 1
        XCTAssertEqual(page.chapterPosition(atPageOffset: 0), page.chapterPosition)
        XCTAssertEqual(page.chapterPosition(atPageOffset: 3), page.chapterPosition + 3)
    }

    /// A negative offset is clamped to the start of the page.
    func testANegativePageOffsetIsClamped() {
        let page = TextPage()
        page.text = "abc"
        XCTAssertEqual(page.chapterPosition(atPageOffset: -5), page.chapterPosition)
    }

    // MARK: - The bookmarks

    /// The identity of a bookmark is the time it was created.
    func testTheBookmarkIdentity() {
        let bookmark = Bookmark(
            time: 1_700_000_000,
            bookName: "书",
            bookAuthor: "作者"
        )
        XCTAssertEqual(bookmark.id, 1_700_000_000)
    }
}
