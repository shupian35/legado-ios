import Foundation

/// The `multipart/form-data` body builder — the port of the upstream
/// `Request.Builder.postMultipart` (`app/src/main/java/io/legado/app/help/http/OkHttpUtils.kt:156`).
public enum MultipartBody {
    /// One part of a multipart body.
    public struct Part {
        /// The form field name.
        public var name: String
        /// The file name — nil for a plain field.
        public var fileName: String?
        /// The part's content type — nil for a plain field.
        public var contentType: String?
        /// The part's payload.
        public var data: Data

        public init(name: String, fileName: String? = nil, contentType: String? = nil, data: Data) {
            self.name = name
            self.fileName = fileName
            self.contentType = contentType
            self.data = data
        }

        /// A plain text field.
        public static func field(_ name: String, _ value: String) -> Part {
            Part(name: name, data: Data(value.utf8))
        }
    }

    /// A random boundary — the upstream uses OkHttp's internal one.
    public static func makeBoundary() -> String {
        "----LegadoBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    /// Encode the parts as a `multipart/form-data` body.
    public static func encode(_ parts: [Part], boundary: String) -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append(Data("\(disposition)\r\n".utf8))
            if let contentType = part.contentType {
                body.append(Data("Content-Type: \(contentType)\r\n".utf8))
            }
            body.append(Data("\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
