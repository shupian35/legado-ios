import Foundation
import XCTest
import SwiftSoup
@testable import LegadoCore

private func trace(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

final class ScratchSoupTests: XCTestCase {
    func testEpubBookInit() throws {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>测试书名</dc:title>
            <dc:creator>测试作者</dc:creator>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head><meta name="dtb:uid" content="book-id"/></head>
          <navMap>
            <navPoint id="n1"><navLabel><text>第一章</text></navLabel><content src="ch1.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
        let data = ZipBuilder.build([
            .init(name: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(name: "META-INF/container.xml", data: Data(container.utf8)),
            .init(name: "OEBPS/content.opf", data: Data(opf.utf8)),
            .init(name: "OEBPS/toc.ncx", data: Data(ncx.utf8)),
            .init(name: "OEBPS/ch1.xhtml", data: Data("<html><body><p>a</p></body></html>".utf8))
        ])
        trace("W1 built")
        let archive = try ZipArchive(data: data)
        trace("W2 archive")
        let book = try EpubBook(archive: archive)
        trace("W3 book \(book.title)")
    }
}