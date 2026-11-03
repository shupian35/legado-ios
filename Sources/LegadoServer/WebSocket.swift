import Foundation

/// SHA-1 — needed for the WebSocket handshake (`Sec-WebSocket-Accept`).
///
/// CryptoKit is Apple-only, so the port carries its own implementation, the
/// same way it does for MD5 (`LegadoCore/Script/ScriptDigest.swift`).
public enum SHA1 {

    public static func hash(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunkStart in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(data[base]) << 24)
                    | (UInt32(data[base + 1]) << 16)
                    | (UInt32(data[base + 2]) << 8)
                    | UInt32(data[base + 3])
            }
            for i in 16..<80 {
                w[i] = rotateLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32)
                switch i {
                case 0..<20: (f, k) = ((b & c) | (~b & d), 0x5A82_7999)
                case 20..<40: (f, k) = (b ^ c ^ d, 0x6ED9_EBA1)
                case 40..<60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                default: (f, k) = (b ^ c ^ d, 0xCA62_C1D6)
                }
                let temp = rotateLeft(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotateLeft(b, 30)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var digest: [UInt8] = []
        for word in [h0, h1, h2, h3, h4] {
            digest.append(UInt8((word >> 24) & 0xff))
            digest.append(UInt8((word >> 16) & 0xff))
            digest.append(UInt8((word >> 8) & 0xff))
            digest.append(UInt8(word & 0xff))
        }
        return digest
    }

    /// The hex digest, lowercase.
    public static func hex(_ message: [UInt8]) -> String {
        hash(message).map { String(format: "%02x", $0) }.joined()
    }

    public static func hex(_ text: String) -> String {
        hex(Array(text.utf8))
    }

    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}

/// The WebSocket handshake and frame codec — the port of the parts of
/// NanoWSD that `web/WebSocketServer.kt` uses.
public enum WebSocket {

    /// The accept token for a client key (RFC 6455 §4.2.2).
    public static func acceptToken(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = SHA1.hash(Array((key + magic).utf8))
        return Data(digest).base64EncodedString()
    }

    /// Whether the request is an upgrade request this server can serve.
    public static func isUpgradeRequest(_ request: HTTPRequestHead) -> Bool {
        let upgrade = request.header("Upgrade")?.lowercased() ?? ""
        let connection = request.header("Connection")?.lowercased() ?? ""
        return upgrade == "websocket" && connection.contains("upgrade")
            && request.header("Sec-WebSocket-Key") != nil
    }

    /// The 101 response.
    public static func handshakeResponse(for request: HTTPRequestHead) -> HTTPResponseMessage {
        guard let key = request.header("Sec-WebSocket-Key") else {
            return .error("missing Sec-WebSocket-Key", code: 400)
        }
        return HTTPResponseMessage(
            code: 101,
            reason: "Switching Protocols",
            headers: [
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": acceptToken(for: key)
            ]
        )
    }

    /// Opcodes used by the API.
    public enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    public struct Frame: Equatable, Sendable {
        public let opcode: Opcode
        public let payload: Data
        public let isFinal: Bool

        public init(opcode: Opcode, payload: Data = Data(), isFinal: Bool = true) {
            self.opcode = opcode
            self.payload = payload
            self.isFinal = isFinal
        }

        /// Text frames carry UTF-8.
        public var text: String {
            String(decoding: payload, as: UTF8.self)
        }
    }

    /// Builds a server-to-client frame (unmasked, as the server must send).
    public static func encode(_ frame: Frame) -> Data {
        var data = Data()
        var first: UInt8 = frame.opcode.rawValue
        if frame.isFinal { first |= 0x80 }
        data.append(first)

        let length = frame.payload.count
        if length < 126 {
            data.append(UInt8(length))
        } else if length <= 0xffff {
            data.append(126)
            data.append(UInt8((length >> 8) & 0xff))
            data.append(UInt8(length & 0xff))
        } else {
            data.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8((UInt64(length) >> UInt64(shift)) & 0xff))
            }
        }
        data.append(frame.payload)
        return data
    }

    /// Encodes a text frame.
    public static func textFrame(_ text: String) -> Data {
        encode(Frame(opcode: .text, payload: Data(text.utf8)))
    }

    /// Parses one client frame. Client frames are always masked.
    ///
    /// - Returns: the frame and the number of bytes consumed, or `nil` when
    ///   the buffer does not yet hold a full frame.
    public static func decode(_ data: Data) throws -> (frame: Frame, consumed: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let isFinal = bytes[0] & 0x80 != 0
        guard let opcode = Opcode(rawValue: bytes[0] & 0x0f) else {
            throw WebSocketError.unsupportedOpcode(bytes[0] & 0x0f)
        }
        let masked = bytes[1] & 0x80 != 0
        var length = Int(bytes[1] & 0x7f)
        var index = 2

        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = (Int(bytes[2]) << 8) | Int(bytes[3])
            index = 4
        } else if length == 127 {
            guard bytes.count >= 10 else { return nil }
            var value: UInt64 = 0
            for offset in 0..<8 { value = (value << 8) | UInt64(bytes[2 + offset]) }
            guard value <= UInt64(Int.max) else { throw WebSocketError.frameTooLarge }
            length = Int(value)
            index = 10
        }

        var maskKey: [UInt8] = []
        if masked {
            guard bytes.count >= index + 4 else { return nil }
            maskKey = Array(bytes[index..<index + 4])
            index += 4
        }
        guard bytes.count >= index + length else { return nil }
        var payload = Array(bytes[index..<index + length])
        if masked, maskKey.count == 4 {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        let frame = Frame(opcode: opcode, payload: Data(payload), isFinal: isFinal)
        return (frame, index + length)
    }
}

public enum WebSocketError: Error, Equatable {
    case unsupportedOpcode(UInt8)
    case frameTooLarge
    case invalidHandshake
}
