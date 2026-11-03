import Foundation

/// Port of `io.legado.app.constant.AppPattern` (only the patterns the rule engine
/// needs) plus the compiled-regexp cache used by `AnalyzeRule`.
///
/// Upstream: app/src/main/java/io/legado/app/constant/AppPattern.kt
public enum RulePatterns {

    // MARK: - Rule markers

    /// `<js>...</js>` or `@js:...`
    public static let jsPatternSource = "<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)"

    /// `{{ ... }}`
    public static let expPatternSource = "\\{\\{([\\w\\W]*?)\\}\\}"

    /// `@put:{ ... }`
    public static let putPatternSource = "@put:(\\{[^}]+?\\})"

    /// `@get:{ key }` or `{{ ... }}`
    public static let evalPatternSource = "@get:\\{[^}]+?\\}|\\{\\{[\\w\\W]*?\\}\\}"

    /// `$1` … `$99`
    public static let regexPatternSource = "\\$\\d{1,2}"

    // MARK: - Compiled patterns

    /// `JS_PATTERN` — case insensitive, like upstream.
    public static let jsPattern = try! NSRegularExpression(
        pattern: jsPatternSource,
        options: [.caseInsensitive]
    )

    /// `EXP_PATTERN`
    public static let expPattern = try! NSRegularExpression(pattern: expPatternSource)

    /// `putPattern` — case insensitive.
    public static let putPattern = try! NSRegularExpression(
        pattern: putPatternSource,
        options: [.caseInsensitive]
    )

    /// `evalPattern` — case insensitive.
    public static let evalPattern = try! NSRegularExpression(
        pattern: evalPatternSource,
        options: [.caseInsensitive]
    )

    /// `regexPattern`
    public static let regexPattern = try! NSRegularExpression(pattern: regexPatternSource)

    // MARK: - Misc content patterns (used by the pipeline / local books)

    public static let imgPattern = "<img[^>]*src=['\"]([^'\"]*(?:['\"][^>]+\\})?)['\"][^>]*>"
    /// The compiled `imgPattern` — group 1 is the `src` of the tag.
    public static let compiledImgPattern = try! NSRegularExpression(
        pattern: imgPattern,
        options: []
    )
    // The default RSS parser extracts the image of an article from the first
    // `<img>` of its description (RssParserDefault.kt:125-133).
    public static let imageTagPatternSource = "(<img [^>]*>)"
    public static let imageSrcPatternSource = "src\\s*=\\s*\"([^\"]+)\""
    public static let imageTagPattern = try! NSRegularExpression(
        pattern: imageTagPatternSource,
        options: []
    )
    public static let imageSrcPattern = try! NSRegularExpression(
        pattern: imageSrcPatternSource,
        options: []
    )
    public static let dataURIRegex = "^data:.*?;base64,(.*)"
    public static let nameRegex = "\\s+作\\s*者.*|\\s+\\S+\\s+著"
    public static let authorRegex = "^\\s*作\\s*者[:：\\s]+|\\s+著"
    public static let fileNameRegex = "[\\\\/:*?\"<>|.]"
    public static let fileNameRegex2 = "[\\\\/:*?\"<>|]"
    public static let splitGroupRegex = "[,;，；]"
    public static let titleNumPattern = "(第)(.+?)(章)"
    public static let debugMessageSymbolRegex = "[⇒◇┌└≡]"
    public static let bookFileRegex = ".*\\.(txt|epub|umd|pdf|mobi|azw3|azw)"
    public static let archiveFileRegex = ".*\\.(zip|rar|7z)$"
    public static let bdRegex = "(\\p{P})+"
    public static let rnRegex = "[\\r\\n]"
    public static let notReadAloudRegex = "^(\\s|\\p{C}|\\p{P}|\\p{Z}|\\p{S})+$"
    public static let xmlContentTypeRegex = "(application|text)/\\w*\\+?xml.*"
    public static let semicolonRegex = ";"
    public static let equalsRegex = "="
    public static let spaceRegex = "\\s+"
    public static let regexCharRegex = "[{}()\\[\\].+*?^$\\\\|]"
    public static let lfRegex = "\n"

    /// The page placeholder of a URL rule — upstream `AnalyzeUrl.pagePattern`.
    public static let pagePatternSource = "<(.*?)>"
    public static let pagePattern = try! NSRegularExpression(pattern: pagePatternSource)

    /// The option block separator of a URL rule — upstream `AnalyzeUrl.paramPattern`.
    public static let paramPatternSource = "\\s*,\\s*(?=\\{)"
    public static let paramPattern = try! NSRegularExpression(pattern: paramPatternSource)

    // MARK: - HTML formatting (upstream `io.legado.app.utils.HtmlFormatter`)

    public static let nbspPattern = try! NSRegularExpression(pattern: "(&nbsp;)+")
    public static let espPattern = try! NSRegularExpression(pattern: "(&ensp;|&emsp;)")
    public static let noPrintPattern = try! NSRegularExpression(
        pattern: "(&thinsp;|&zwnj;|&zwj;|\u{2009}|\u{200C}|\u{200D})"
    )
    public static let wrapHtmlPattern = try! NSRegularExpression(
        pattern: "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>"
    )
    public static let commentPattern = try! NSRegularExpression(pattern: "<!--[^>]*-->")
    public static let notImgHtmlPattern = try! NSRegularExpression(
        pattern: "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>"
    )
    public static let otherHtmlPattern = try! NSRegularExpression(
        pattern: "</?[a-zA-Z]+(?=[ >])[^<>]*>"
    )
    /// Upstream `HtmlFormatter.formatImagePattern` — three alternatives:
    /// a `src` carrying a `{…}` option block, a plain `src`/`data-src`, and any `data-*` attribute.
    public static let formatImagePatternSource =
        "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>"
        + "|<img[^>]*\\s(?:data-src|src)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>"
        + "|<img[^>]*\\sdata-[^=>]*=\\s*['\"]([^'\">]*)['\"][^>]*>"
    public static let formatImagePattern = try! NSRegularExpression(
        pattern: formatImagePatternSource,
        options: [.caseInsensitive]
    )
    public static let indent1Pattern = try! NSRegularExpression(pattern: "\\s*\\n+\\s*")
    public static let indent2Pattern = try! NSRegularExpression(pattern: "^[\\n\\s]+")
    public static let lastPattern = try! NSRegularExpression(pattern: "[\\n\\s]+$")

    /// The book name / author cleanup patterns — upstream `AppPattern.nameRegex` / `authorRegex`.
    public static let namePattern = try! NSRegularExpression(pattern: nameRegex)
    public static let authorPattern = try! NSRegularExpression(pattern: authorRegex)
}

// MARK: - Small helpers shared by the rule engine

extension String {
    /// Java's `Char <= ' '` — used by upstream to trim control characters.
    @inline(__always)
    func isJavaSpaceOrLess() -> Bool {
        guard let ascii = self.unicodeScalars.first, ascii.isASCII else { return false }
        return ascii.value <= 0x20
    }

    /// Faithful port of Kotlin's `String.trim { it <= ' ' }`.
    func trimmingJavaSpaces() -> String {
        var scalars = Array(self.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, String(scalars[start]).isJavaSpaceOrLess() { start += 1 }
        while end > start, String(scalars[end - 1]).isJavaSpaceOrLess() { end -= 1 }
        scalars = Array(scalars[start..<end])
        return String(String.UnicodeScalarView(scalars))
    }

    /// Kotlin's `String.startsWith(prefix, ignoreCase)`.
    func startsWithCaseInsensitive(_ prefix: String) -> Bool {
        guard prefix.count <= count else { return false }
        let a = self.prefix(prefix.count)
        return a.compare(prefix, options: [.caseInsensitive]) == .orderedSame
    }

    /// Kotlin's `String.substring(startIndex, endIndex)` on UTF-16 offsets.
    /// Returns `nil` when the range is out of bounds (Kotlin would throw).
    func substringUTF16(_ start: Int, _ end: Int) -> String? {
        let utf16 = Array(self.utf16)
        guard start >= 0, end <= utf16.count, start <= end else { return nil }
        return String(decoding: utf16[start..<end], as: UTF16.self)
    }

    /// Number of UTF-16 code units — Java `String.length`.
    var utf16Length: Int { utf16.count }

    /// Kotlin's `String.splitNotBlank(delimiter)` — split and drop blank parts.
    func splitNotBlank(_ delimiter: String) -> [String] {
        guard !delimiter.isEmpty else { return [self] }
        return components(separatedBy: delimiter).filter { !$0.isBlank }
    }
}

/// Small LRU cache mirroring Kotlin's `getOrPutLimit(key, limit) { … }`.
public final class LimitedCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private let limit: Int

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func value(for key: Key) -> Value? { storage[key] }

    public func put(_ key: Key, _ value: Value) {
        if storage[key] == nil {
            order.append(key)
            if order.count > limit {
                let evicted = order.removeFirst()
                storage.removeValue(forKey: evicted)
            }
        }
        storage[key] = value
    }

    /// `getOrPutLimit(key, limit) { block }`
    public func getOrPut(_ key: Key, _ block: () -> Value) -> Value {
        if let existing = storage[key] { return existing }
        let fresh = block()
        put(key, fresh)
        return fresh
    }

    public var count: Int { storage.count }
}

extension Character {
    /// Java's Char <= ' ' — the test upstream uses to skip whitespace.
    @inline(__always)
    func isJavaSpaceOrLess() -> Bool {
        guard let ascii = unicodeScalars.first, ascii.isASCII else { return false }
        return ascii.value <= 0x20
    }
}
extension String {
    /// Kotlin's String.isBlank() — true for an empty string or one that
    /// contains only whitespace.
    @inline(__always)
    var isBlank: Bool {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
                continue
            case 0x2000...0x200A, 0x200B...0x200F, 0x202F...0x202F, 0x205F...0x205F:
                continue
            default:
                if Character(scalar).isWhitespace { continue }
                return false
            }
        }
        return true
    }
}