//
//  MultipartTests.swift
//  LegadoServerTests
//
//  The `multipart/form-data` parser used by the upload route.
//

import XCTest
@testable import LegadoServer

final class MultipartTests: XCTestCase {

    private let boundary = "----WebKitFormBoundaryABC"

    private func body(_ parts: [(String, String?, String)]) -> Data {
        var text = ""
        for (name, fileName, value) in parts {
            text += "--\(boundary)\r\n"
            var disposition = "Content-Disposition: form-data; name=\"\(name)\""
            if let fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            text += disposition + "\r\n"
            text += "Content-Type: application/octet-stream\r\n\r\n"
            text += value + "\r\n"
        }
        text += "--\(boundary)--\r\n"
        return Data(text.utf8)
    }

    func testTheBoundaryIsReadFromTheContentType() {
        XCTAssertEqual(
            MultipartParser.boundary(in: "multipart/form-data; boundary=\(boundary)"),
            boundary
        )
        XCTAssertEqual(
            MultipartParser.boundary(in: "multipart/form-data; boundary=\"\(boundary)\""),
            boundary
        )
        XCTAssertNil(MultipartParser.boundary(in: "application/json"))
        XCTAssertNil(MultipartParser.boundary(in: nil))
    }

    func testThePartsAreParsed() throws {
        let data = body([("fileName", nil, "book.txt"), ("fileData", "book.txt", "内容")])
        let parts = try MultipartParser.parse(
            body: data,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].name, "fileName")
        XCTAssertNil(parts[0].fileName)
        XCTAssertEqual(parts[0].text, "book.txt")
        XCTAssertEqual(parts[1].name, "fileData")
        XCTAssertEqual(parts[1].fileName, "book.txt")
        XCTAssertEqual(parts[1].text, "内容")
    }

    func testBinaryContentSurvives() throws {
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"fileData\"; filename=\"a.epub\"\r\n".utf8))
        data.append(Data("Content-Type: application/epub+zip\r\n\r\n".utf8))
        data.append(Data([0x00, 0x01, 0x0D, 0x0A, 0xFF]))
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let parts = try MultipartParser.parse(
            body: data,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].data, Data([0x00, 0x01, 0x0D, 0x0A, 0xFF]))
        XCTAssertEqual(parts[0].contentType, "application/epub+zip")
    }

    func testAMissingBoundaryIsAnError() {
        XCTAssertThrowsError(try MultipartParser.parse(body: Data(), contentType: "application/json"))
    }

    func testAMalformedBodyIsAnError() {
        XCTAssertThrowsError(
            try MultipartParser.parse(
                body: Data("garbage".utf8),
                contentType: "multipart/form-data; boundary=\(boundary)"
            )
        )
    }
}
