//
//  ScriptEngineTests.swift
//  LegadoCoreTests
//
//  Tests for the platform independent part of the script layer: the MD5
//  digest used by `java.md5` and `MD5Utils.md5Encode16`, and the stub engine
//  that Linux CI builds use instead of JavaScriptCore.
//

import XCTest
@testable import LegadoCore

final class ScriptDigestTests: XCTestCase {
    func testEmptyInput() {
        XCTAssertEqual(
            ScriptDigest.md5Hex(Data()),
            "d41d8cd98f00b204e9800998ecf8427e"
        )
    }

    func testKnownVectors() {
        XCTAssertEqual(
            ScriptDigest.md5Hex("a"),
            "0cc175b9c0f1b6a831c399e269772661"
        )
        XCTAssertEqual(
            ScriptDigest.md5Hex("abc"),
            "900150983cd24fb0d6963f7d28e17f72"
        )
        XCTAssertEqual(
            ScriptDigest.md5Hex("message digest"),
            "f96b697d7cb7938d525a2f31aaf161d0"
        )
        XCTAssertEqual(
            ScriptDigest.md5Hex("abcdefghijklmnopqrstuvwxyz"),
            "c3fcd3d76192e4007dfb496cca67e13b"
        )
        XCTAssertEqual(
            ScriptDigest.md5Hex("12345678901234567890123456789012345678901234567890123456789012345678901234567890"),
            "57edf4a22be3c955ac49da2e2107b67a"
        )
    }

    func testUnicodeInput() {
        // The digest is over the UTF-8 bytes.
        XCTAssertEqual(ScriptDigest.md5Hex("阅读"), ScriptDigest.md5Hex(Data("阅读".utf8)))
        XCTAssertEqual(ScriptDigest.md5Hex("阅读").count, 32)
    }

    func testMd5Encode16IsTheFirstSixteenCharacters() {
        let full = ScriptDigest.md5Hex("chapter")
        XCTAssertEqual(ScriptDigest.md5Encode16("chapter"), String(full.prefix(16)))
        XCTAssertEqual(ScriptDigest.md5Encode16("chapter").count, 16)
    }
}

final class ScriptEngineFallbackTests: XCTestCase {
    func testUnavailableEngineReportsTheMissingCapability() {
        let engine = UnavailableScriptEngine()
        XCTAssertThrowsError(try engine.evaluate("1 + 1", bindings: [:])) { error in
            guard case ScriptEngineError.unsupportedPlatform = error else {
                return XCTFail("expected unsupportedPlatform, got \(error)")
            }
        }
    }
}

final class ScriptEnvironmentTests: XCTestCase {
    func testEnvironmentKeepsItsDependencies() {
        let environment = ScriptEnvironment(defaultHeaders: ["User-Agent": "Legado"])
        XCTAssertEqual(environment.defaultHeaders["User-Agent"], "Legado")
        XCTAssertNil(environment.network)
        XCTAssertNil(environment.files)
    }
}
