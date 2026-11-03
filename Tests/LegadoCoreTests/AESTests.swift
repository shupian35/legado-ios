import XCTest

@testable import LegadoCore

final class AESTests: XCTestCase {

    /// FIPS-197 / NIST SP 800-38A vectors — a wrong S-box, mix-columns or key
    /// expansion shows up here immediately.
    func testEncryptsKnownAES128Vectors() throws {
        // FIPS-197 appendix C.1
        let key: [UInt8] = (0x00...0x0f).map { UInt8($0) }
        var block = Array("00112233445566778899aabbccddeeff".hexBytes())
        let roundKeys = try AES.expandKey(key)
        AES.encryptBlock(&block, roundKeys: roundKeys)
        XCTAssertEqual(block.toHex(), "69c4e0d86a7b0430d8cdb78070b4c55a")

        var restored = block
        AES.decryptBlock(&restored, roundKeys: roundKeys)
        XCTAssertEqual(restored.toHex(), "00112233445566778899aabbccddeeff")
    }

    func testEncryptsKnownAES256Vector() throws {
        // FIPS-197 appendix C.3
        let key = Array("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f".hexBytes())
        var block = Array("00112233445566778899aabbccddeeff".hexBytes())
        let roundKeys = try AES.expandKey(key)
        AES.encryptBlock(&block, roundKeys: roundKeys)
        XCTAssertEqual(block.toHex(), "8ea2b7ca516745bfeafc49904b496089")
    }

    /// NIST SP 800-38A F.2.1 (CBC-AES128).
    func testCBCMatchesNISTVector() throws {
        let key = Array("2b7e151628aed2a6abf7158809cf4f3c".hexBytes())
        let iv = Array("000102030405060708090a0b0c0d0e0f".hexBytes())
        let plaintext = Array(
            "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51".hexBytes()
        )
        let ciphertext = try AES.encryptCBC(plaintext, key: key, iv: iv)
        XCTAssertEqual(
            ciphertext.prefix(32).toHex(),
            "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2"
        )
        let decrypted = try AES.decryptCBC(ciphertext, key: key, iv: iv)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testECBRoundTripAddsAndStripsPadding() throws {
        let key = Array("0123456789abcdef".utf8)
        for length in [0, 1, 15, 16, 17, 32] {
            let plaintext = Array(repeating: UInt8(0x41), count: length)
            let ciphertext = try AES.encryptECB(plaintext, key: key)
            XCTAssertEqual(ciphertext.count % 16, 0)
            XCTAssertGreaterThan(ciphertext.count, plaintext.count)
            XCTAssertEqual(try AES.decryptECB(ciphertext, key: key), plaintext)
        }
    }

    func testInvalidKeyLengthThrows() {
        XCTAssertThrowsError(try AES.expandKey([1, 2, 3]))
    }

    // MARK: - Backup cipher

    func testBackupCipherKeyIsTheFirst16HexCharsOfMD5() {
        let cipher = BackupCipher(password: nil)
        // MD5("") = d41d8cd98f00b204e9800998ecf8427e
        XCTAssertEqual(String(decoding: cipher.key, as: UTF8.self), "d41d8cd98f00b204")
        XCTAssertEqual(cipher.key.count, 16)
    }

    func testBackupCipherRoundTrip() throws {
        let cipher = BackupCipher(password: "legado")
        let json = "[{\"name\":\"坚果云\",\"type\":\"WEBDAV\"}]"
        let encrypted = try cipher.encryptBase64(json)
        XCTAssertNotEqual(encrypted, json)
        XCTAssertEqual(try cipher.decrypt(encrypted), json)
    }

    func testBackupCipherEmptyString() throws {
        let cipher = BackupCipher(password: "")
        let encrypted = try cipher.encryptBase64("")
        XCTAssertEqual(try cipher.decrypt(encrypted), "")
    }
}

// MARK: - Hex helpers

extension String {
    func hexBytes() -> [UInt8] {
        var result: [UInt8] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: 2, limitedBy: endIndex) ?? endIndex
            guard let byte = UInt8(self[index..<next], radix: 16) else { return result }
            result.append(byte)
            index = next
        }
        return result
    }
}

extension Sequence where Element == UInt8 {
    func toHex() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
