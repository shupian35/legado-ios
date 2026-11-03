import XCTest

@testable import LegadoCore

/// The tests of the remote books — the WebDAV listing, the sorting and the
/// origin of an imported book (upstream `RemoteBookWebDav` +
/// `RemoteBookViewModel`).
final class RemoteBookImportTests: XCTestCase {

    private func makeImporter(
        rootPath: String = "books/",
        serverID: Int64? = nil,
        xml: String
    ) -> RemoteBookImporter {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: xml, code: 207)
        }
        let configuration = WebDavConfiguration(
            url: "https://dav.example.com/dav/",
            username: "user",
            password: "secret"
        )
        let client = WebDavClient(configuration: configuration, httpClient: stub)
        return RemoteBookImporter(client: client, rootPath: rootPath, serverID: serverID)
    }

    private let listingXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/dav/books/</d:href>
        <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/books/sub/</d:href>
        <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/books/novel.txt</d:href>
        <d:propstat><d:prop>
          <d:getcontentlength>1024</d:getcontentlength>
          <d:getlastmodified>Mon, 14 Nov 2023 10:00:00 GMT</d:getlastmodified>
          <d:resourcetype/>
        </d:prop></d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/books/novel.epub</d:href>
        <d:propstat><d:prop>
          <d:getcontentlength>2048</d:getcontentlength>
          <d:getlastmodified>Tue, 15 Nov 2023 10:00:00 GMT</d:getlastmodified>
          <d:resourcetype/>
        </d:prop></d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/books/notes.html</d:href>
        <d:propstat><d:prop>
          <d:getcontentlength>10</d:getcontentlength>
          <d:resourcetype/>
        </d:prop></d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/books/pack.zip</d:href>
        <d:propstat><d:prop>
          <d:getcontentlength>4096</d:getcontentlength>
          <d:resourcetype/>
        </d:prop></d:propstat>
      </d:response>
    </d:multistatus>
    """

    // MARK: - The listing

    func testListsOnlyTheDirectoriesAndTheBooks() async throws {
        let importer = makeImporter(xml: listingXML)
        let books = try await importer.list()
        let names = books.map(\.filename).sorted()
        XCTAssertEqual(names, ["novel.epub", "novel.txt", "pack.zip", "sub"])
        XCTAssertTrue(books.first { $0.filename == "sub" }?.isDir ?? false)
        XCTAssertFalse(books.first { $0.filename == "novel.txt" }?.isDir ?? true)
        XCTAssertEqual(books.first { $0.filename == "novel.txt" }?.size, 1024)
    }

    func testTheRootPathIsUsedForTheRequest() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: self.listingXML, code: 207)
        }
        let client = WebDavClient(
            configuration: WebDavConfiguration(url: "https://dav.example.com/dav/", username: "u", password: "p"),
            httpClient: stub
        )
        let importer = RemoteBookImporter(client: client, rootPath: "books/")
        _ = try await importer.list(subPath: "sub")
        XCTAssertEqual(stub.requests.first?.url, "https://dav.example.com/dav/books/sub")
    }

    // MARK: - The sorting

    func testTheAscendingSortPutsTheFoldersFirst() {
        let books = [
            RemoteBook(filename: "b.txt", path: "b.txt", size: 1, lastModify: 20, contentType: "txt"),
            RemoteBook(filename: "folder", path: "folder", contentType: "folder"),
            RemoteBook(filename: "a.txt", path: "a.txt", size: 1, lastModify: 30, contentType: "txt")
        ]
        let sorted = RemoteBookImporter.sorted(books, by: .name, ascending: true)
        XCTAssertEqual(sorted.map(\.filename), ["folder", "a.txt", "b.txt"])
    }

    func testTheDescendingSortPutsTheFilesFirst() {
        let books = [
            RemoteBook(filename: "b.txt", path: "b.txt", size: 1, lastModify: 20, contentType: "txt"),
            RemoteBook(filename: "folder", path: "folder", contentType: "folder"),
            RemoteBook(filename: "a.txt", path: "a.txt", size: 1, lastModify: 30, contentType: "txt")
        ]
        let sorted = RemoteBookImporter.sorted(books, by: .name, ascending: false)
        XCTAssertEqual(sorted.map(\.filename), ["b.txt", "a.txt", "folder"])
    }

    func testTheModificationSort() {
        let books = [
            RemoteBook(filename: "old.txt", path: "old.txt", lastModify: 10, contentType: "txt"),
            RemoteBook(filename: "new.txt", path: "new.txt", lastModify: 20, contentType: "txt")
        ]
        XCTAssertEqual(
            RemoteBookImporter.sorted(books, by: .modification, ascending: true).map(\.filename),
            ["old.txt", "new.txt"]
        )
        XCTAssertEqual(
            RemoteBookImporter.sorted(books, by: .modification, ascending: false).map(\.filename),
            ["new.txt", "old.txt"]
        )
    }

    // MARK: - The name comparison

    func testTheNumbersAreComparedNumerically() {
        XCTAssertTrue(AlphanumComparator.compare("第2章", "第10章") < 0)
        XCTAssertTrue(AlphanumComparator.compare("第10章", "第2章") > 0)
        XCTAssertEqual(AlphanumComparator.compare("book2", "book2"), 0)
        XCTAssertTrue(AlphanumComparator.compare("a", "ab") < 0)
        XCTAssertTrue(AlphanumComparator.compare("abc", "abd") < 0)
    }

    // MARK: - The origin

    func testTheOriginCarriesTheServerID() {
        let importer = makeImporter(serverID: 7, xml: listingXML)
        let book = RemoteBook(filename: "a.txt", path: "books/a.txt", contentType: "txt")
        XCTAssertEqual(importer.origin(for: book), "webDav::books/a.txt,{\"serverID\":7}")
    }

    func testTheOriginWithoutAServer() {
        let importer = makeImporter(xml: listingXML)
        let book = RemoteBook(filename: "a.txt", path: "books/a.txt", contentType: "txt")
        XCTAssertEqual(importer.origin(for: book), "webDav::books/a.txt")
    }
}
