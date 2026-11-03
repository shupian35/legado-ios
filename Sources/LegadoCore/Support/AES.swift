import Foundation

/// A self-contained AES implementation (128/192/256, ECB and CBC) with
/// PKCS#7 padding and base64 helpers.
///
/// Why hand-written: the backup format is encrypted with `javax.crypto`
/// AES, and the port must be able to **read an Android backup** and produce one
/// Android can read. CryptoKit exists only on Apple platforms, so relying on it
/// would make the Linux build (which is where the port is verified) unable to
/// round-trip a backup. The upstream cipher is hutool's
/// `cn.hutool.crypto.symmetric.AES(byte[] key)`, which defaults to
/// **AES/ECB/PKCS5Padding** (`help/storage/BackupAES.kt:7-9`).
public enum AESError: Error, Equatable {
    case invalidKeyLength(Int)
    case invalidBlockLength(Int)
    case invalidPadding
}

public enum AES {

    // MARK: - Key schedule

    /// Expands a key into the round keys. `key.count` must be 16, 24 or 32.
    static func expandKey(_ key: [UInt8]) throws -> [[UInt8]] {
        guard [16, 24, 32].contains(key.count) else {
            throw AESError.invalidKeyLength(key.count)
        }
        let nk = key.count / 4
        let rounds = nk + 6
        let totalWords = 4 * (rounds + 1)

        var words: [[UInt8]] = stride(from: 0, to: key.count, by: 4).map {
            Array(key[$0..<$0 + 4])
        }
        var rcon: UInt8 = 1
        for i in nk..<totalWords {
            var temp = words[i - 1]
            if i % nk == 0 {
                temp = [temp[1], temp[2], temp[3], temp[0]]        // RotWord
                temp = temp.map { sbox[Int($0)] }                  // SubWord
                temp[0] ^= rcon
                rcon = xtime(rcon)
            } else if nk > 6 && i % nk == 4 {
                temp = temp.map { sbox[Int($0)] }
            }
            words.append(zip(words[i - nk], temp).map { $0 ^ $1 })
        }
        return stride(from: 0, to: totalWords, by: 4).map { index in
            words[index] + words[index + 1] + words[index + 2] + words[index + 3]
        }
    }

    // MARK: - Block operations

    /// Encrypts one 16-byte block in place.
    static func encryptBlock(_ block: inout [UInt8], roundKeys: [[UInt8]]) {
        addRoundKey(&block, roundKeys[0])
        for round in 1..<roundKeys.count {
            subBytes(&block)
            shiftRows(&block)
            if round != roundKeys.count - 1 { mixColumns(&block) }
            addRoundKey(&block, roundKeys[round])
        }
    }

    /// Decrypts one 16-byte block in place.
    static func decryptBlock(_ block: inout [UInt8], roundKeys: [[UInt8]]) {
        addRoundKey(&block, roundKeys[roundKeys.count - 1])
        for round in stride(from: roundKeys.count - 2, through: 1, by: -1) {
            invShiftRows(&block)
            invSubBytes(&block)
            addRoundKey(&block, roundKeys[round])
            invMixColumns(&block)
        }
        invShiftRows(&block)
        invSubBytes(&block)
        addRoundKey(&block, roundKeys[0])
    }

    private static func addRoundKey(_ block: inout [UInt8], _ key: [UInt8]) {
        for i in 0..<16 { block[i] ^= key[i] }
    }

    private static func subBytes(_ block: inout [UInt8]) {
        for i in 0..<16 { block[i] = sbox[Int(block[i])] }
    }

    private static func invSubBytes(_ block: inout [UInt8]) {
        for i in 0..<16 { block[i] = invSbox[Int(block[i])] }
    }

    /// The state is column-major: `state[r][c] == block[r + 4c]`.
    private static func shiftRows(_ block: inout [UInt8]) {
        var shifted = block
        for row in 0..<4 {
            for column in 0..<4 {
                shifted[row + 4 * column] = block[row + 4 * ((column + row) % 4)]
            }
        }
        block = shifted
    }

    private static func invShiftRows(_ block: inout [UInt8]) {
        var shifted = block
        for row in 0..<4 {
            for column in 0..<4 {
                shifted[row + 4 * ((column + row) % 4)] = block[row + 4 * column]
            }
        }
        block = shifted
    }

    private static func mixColumns(_ block: inout [UInt8]) {
        for column in 0..<4 {
            let offset = 4 * column
            let a0 = block[offset]
            let a1 = block[offset + 1]
            let a2 = block[offset + 2]
            let a3 = block[offset + 3]
            block[offset] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3
            block[offset + 1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3
            block[offset + 2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3)
            block[offset + 3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3)
        }
    }

    private static func invMixColumns(_ block: inout [UInt8]) {
        for column in 0..<4 {
            let offset = 4 * column
            let a0 = block[offset]
            let a1 = block[offset + 1]
            let a2 = block[offset + 2]
            let a3 = block[offset + 3]
            block[offset] = mul(a0, 0x0e) ^ mul(a1, 0x0b) ^ mul(a2, 0x0d) ^ mul(a3, 0x09)
            block[offset + 1] = mul(a0, 0x09) ^ mul(a1, 0x0e) ^ mul(a2, 0x0b) ^ mul(a3, 0x0d)
            block[offset + 2] = mul(a0, 0x0d) ^ mul(a1, 0x09) ^ mul(a2, 0x0e) ^ mul(a3, 0x0b)
            block[offset + 3] = mul(a0, 0x0b) ^ mul(a1, 0x0d) ^ mul(a2, 0x09) ^ mul(a3, 0x0e)
        }
    }

    @inline(__always)
    private static func xtime(_ value: UInt8) -> UInt8 {
        ((value << 1) ^ ((value & 0x80) != 0 ? 0x1b : 0)) & 0xff
    }

    /// Multiplication in GF(2^8).
    private static func mul(_ value: UInt8, _ factor: UInt8) -> UInt8 {
        var a = value
        var b = factor
        var result: UInt8 = 0
        while b != 0 {
            if b & 1 != 0 { result ^= a }
            a = xtime(a)
            b >>= 1
        }
        return result
    }

    // MARK: - Modes

    /// ECB encryption with PKCS#7 padding.
    public static func encryptECB(_ plaintext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        let roundKeys = try expandKey(key)
        var padded = plaintext
        let pad = 16 - padded.count % 16
        padded.append(contentsOf: Array(repeating: UInt8(pad), count: pad))
        var output = [UInt8]()
        output.reserveCapacity(padded.count)
        var index = 0
        while index < padded.count {
            var block = Array(padded[index..<index + 16])
            encryptBlock(&block, roundKeys: roundKeys)
            output.append(contentsOf: block)
            index += 16
        }
        return output
    }

    /// ECB decryption, stripping PKCS#7 padding.
    public static func decryptECB(_ ciphertext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard ciphertext.count % 16 == 0 else {
            throw AESError.invalidBlockLength(ciphertext.count)
        }
        let roundKeys = try expandKey(key)
        var output = [UInt8]()
        output.reserveCapacity(ciphertext.count)
        var index = 0
        while index < ciphertext.count {
            var block = Array(ciphertext[index..<index + 16])
            decryptBlock(&block, roundKeys: roundKeys)
            output.append(contentsOf: block)
            index += 16
        }
        return try stripPadding(output)
    }

    /// CBC encryption with PKCS#7 padding.
    public static func encryptCBC(
        _ plaintext: [UInt8],
        key: [UInt8],
        iv: [UInt8]
    ) throws -> [UInt8] {
        guard iv.count == 16 else { throw AESError.invalidBlockLength(iv.count) }
        let roundKeys = try expandKey(key)
        var padded = plaintext
        let pad = 16 - padded.count % 16
        padded.append(contentsOf: Array(repeating: UInt8(pad), count: pad))
        var output = [UInt8]()
        var previous = iv
        var index = 0
        while index < padded.count {
            var block = zip(padded[index..<index + 16], previous).map { $0 ^ $1 }
            encryptBlock(&block, roundKeys: roundKeys)
            output.append(contentsOf: block)
            previous = block
            index += 16
        }
        return output
    }

    /// CBC decryption, stripping PKCS#7 padding.
    public static func decryptCBC(
        _ ciphertext: [UInt8],
        key: [UInt8],
        iv: [UInt8]
    ) throws -> [UInt8] {
        guard ciphertext.count % 16 == 0 else {
            throw AESError.invalidBlockLength(ciphertext.count)
        }
        guard iv.count == 16 else { throw AESError.invalidBlockLength(iv.count) }
        let roundKeys = try expandKey(key)
        var output = [UInt8]()
        var previous = iv
        var index = 0
        while index < ciphertext.count {
            let block = Array(ciphertext[index..<index + 16])
            var decrypted = block
            decryptBlock(&decrypted, roundKeys: roundKeys)
            output.append(contentsOf: zip(decrypted, previous).map { $0 ^ $1 })
            previous = block
            index += 16
        }
        return try stripPadding(output)
    }

    private static func stripPadding(_ data: [UInt8]) throws -> [UInt8] {
        guard let last = data.last, last >= 1, last <= 16, data.count >= Int(last) else {
            throw AESError.invalidPadding
        }
        let paddingLength = Int(last)
        guard data.suffix(paddingLength).allSatisfy({ $0 == last }) else {
            throw AESError.invalidPadding
        }
        return Array(data.dropLast(paddingLength))
    }

    // MARK: - Tables

    private static let sbox: [UInt8] = [
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    ]

    private static let invSbox: [UInt8] = [
        0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
        0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
        0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
        0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
        0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
        0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
        0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
        0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
        0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
        0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
        0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
        0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
        0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
        0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
        0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
        0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
    ]
}

/// The backup cipher — the port of `help/storage/BackupAES.kt`.
///
/// The key is the **ASCII of the first 16 hex characters of the MD5 of the
/// password**, i.e. `MD5Utils.md5Encode(password).encodeToByteArray(0, 16)`.
/// An unset password therefore yields the well-known key `d41d8cd98f00b204`
/// (the MD5 of the empty string) — a real upstream weakness, preserved here so
/// that Android backups decrypt.
public struct BackupCipher: Equatable, Sendable {
    public let key: [UInt8]

    public init(password: String?) {
        let hex = ScriptDigest.md5Hex(password ?? "")
        key = Array(hex.utf8.prefix(16))
    }

    /// The upstream `encryptBase64`.
    public func encryptBase64(_ text: String) throws -> String {
        let encrypted = try AES.encryptECB(Array(text.utf8), key: key)
        return Data(encrypted).base64EncodedString()
    }

    /// The upstream `decryptStr`.
    public func decrypt(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else {
            throw AESError.invalidPadding
        }
        let decrypted = try AES.decryptECB(Array(data), key: key)
        return String(decoding: decrypted, as: UTF8.self)
    }
}
