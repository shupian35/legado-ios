//
//  SharedTextTests.swift
//  LegadoCoreTests
//
//  The tests of the shared text — upstream
//  `app/src/main/java/io/legado/app/receiver/SharedReceiverActivity.kt`.
//

import XCTest
@testable import LegadoCore

final class SharedTextTests: XCTestCase {

    // MARK: - The action

    func testABlankTextDoesNothing() {
        XCTAssertEqual(SharedText.action(for: ""), .none)
        XCTAssertEqual(SharedText.action(for: "   \n "), .none)
    }

    func testAnAddressIsImported() {
        XCTAssertEqual(SharedText.action(for: "https://example.com/source.json"), .importAddress("https://example.com/source.json"))
        XCTAssertEqual(SharedText.action(for: "http://example.com"), .importAddress("http://example.com"))
    }

    func testTheFirstAddressOfTheTextIsUsed() {
        // Upstream `dispose(text)` collects every address but opens the main
        // activity; the port imports the first one.
        let action = SharedText.action(for: "look at https://example.com/a.json and http://example.com/b.json")
        XCTAssertEqual(action, .importAddress("https://example.com/a.json"))
    }

    func testAnyOtherTextIsSearched() {
        XCTAssertEqual(SharedText.action(for: "三体"), .search("三体"))
        XCTAssertEqual(SharedText.action(for: "  平凡的世界  "), .search("平凡的世界"))
    }

    func testATextThatOnlyLooksLikeAnAddressIsSearched() {
        // The upstream matches `http.+` — a word that starts with "http" but is
        // not an address is imported anyway; the port follows the upstream.
        XCTAssertEqual(SharedText.action(for: "http"), .importAddress("http"))
    }

    // MARK: - The deep links

    func testTheImportLinkCarriesTheAddress() throws {
        let url = try XCTUnwrap(SharedText.deepLink(for: .importAddress("https://example.com/a.json")))
        XCTAssertEqual(url.scheme, "legado")
        XCTAssertEqual(url.host, "importonline")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first { $0.name == "src" }?.value, "https://example.com/a.json")
    }

    func testTheSearchLinkCarriesTheKeyword() throws {
        let url = try XCTUnwrap(SharedText.deepLink(for: .search("三体")))
        XCTAssertEqual(url.scheme, "legado")
        XCTAssertEqual(url.host, "search")
        XCTAssertEqual(DeepLinkSearch.keyword(from: url), "三体")
    }

    func testTheReadAloudLinkIsTheShortcut() throws {
        let url = try XCTUnwrap(SharedText.deepLink(for: .readAloud))
        XCTAssertEqual(DeepLink.shortcut(from: url), .readAloud)
    }

    func testNoLinkForAnEmptyText() {
        XCTAssertNil(SharedText.deepLink(for: .none))
    }

    // MARK: - The search keyword

    func testTheKeywordOfASearchLink() {
        let url = URL(string: "legado://search?key=%E4%B8%89%E4%BD%93")!
        XCTAssertEqual(DeepLinkSearch.keyword(from: url), "三体")
    }

    func testTheAliasSchemeIsAccepted() {
        let url = URL(string: "yuedu://search?key=abc")!
        XCTAssertEqual(DeepLinkSearch.keyword(from: url), "abc")
    }

    func testALinkWithoutAKeywordHasNone() {
        XCTAssertNil(DeepLinkSearch.keyword(from: URL(string: "legado://search")!))
        XCTAssertNil(DeepLinkSearch.keyword(from: URL(string: "legado://search?key=")!))
    }

    func testAnotherLinkHasNoKeyword() {
        XCTAssertNil(DeepLinkSearch.keyword(from: URL(string: "legado://import?src=https://example.com")!))
        XCTAssertNil(DeepLinkSearch.keyword(from: URL(string: "https://example.com/search?key=abc")!))
    }
}
