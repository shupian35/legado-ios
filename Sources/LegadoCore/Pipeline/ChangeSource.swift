//
//  ChangeSource.swift
//  LegadoCore
//
//  Changing the book source (换源).
//
//  Upstream `ui/book/changesource/ChangeBookSourceViewModel.kt` (580 lines):
//
//  * the enabled sources are searched (optionally filtered by a group) with
//    the book NAME as the key;
//  * a result is kept when the title matches EXACTLY and — only when the
//    "校验作者" option is on — the author CONTAINS the author of the book;
//  * the results are ranked by the user score of the book, the user score of
//    the source and the custom order of the source; with the "加载字数"
//    option the chapter word count and the chapter number rank first;
//  * switching re-fetches the chapter list and maps the reading progress
//    onto the new list by the chapter name similarity.
//
//  The port reproduces that behaviour in `LegadoCore` so that it can be
//  tested on Linux; the UI lives in `LegadoUI`.
//

import Foundation

/// The options of the change-source search.
public struct ChangeSourceOptions: Equatable, Sendable {
    /// Whether the author is checked (`校验作者`).
    public var checkAuthor: Bool
    /// Whether the detail page is loaded (`加载详情页`).
    public var loadInfo: Bool
    /// Whether the chapter list is loaded (`加载目录`).
    public var loadToc: Bool
    /// Whether the word count of one chapter is measured (`加载字数`).
    public var loadWordCount: Bool
    /// The source group to search in (nil = all the groups).
    public var group: String?
    /// The user scores of the books (`origin_name_author` → the score).
    public var bookScores: [String: Int]
    /// The user scores of the sources (`origin` → the score).
    public var sourceScores: [String: Int]

    public init(
        checkAuthor: Bool = false,
        loadInfo: Bool = false,
        loadToc: Bool = false,
        loadWordCount: Bool = false,
        group: String? = nil,
        bookScores: [String: Int] = [:],
        sourceScores: [String: Int] = [:]
    ) {
        self.checkAuthor = checkAuthor
        self.loadInfo = loadInfo
        self.loadToc = loadToc
        self.loadWordCount = loadWordCount
        self.group = group
        self.bookScores = bookScores
        self.sourceScores = sourceScores
    }
}

/// One candidate of the change-source search.
public struct ChangeSourceCandidate: Equatable, Sendable {
    /// The book of the new source.
    public var book: Book
    /// The URL of the source the book came from.
    public var sourceUrl: String
    /// The name of that source.
    public var sourceName: String
    /// The custom order of the source.
    public var originOrder: Int64
    /// The measured word count of one chapter (-1 when it failed).
    public var chapterWordCount: Int
    /// The text of the measured chapter (the upstream `chapterWordCountText`).
    public var chapterWordCountText: String?
    /// The chapter list, when it was loaded.
    public var toc: [BookChapter]?
    /// The response time of the source in milliseconds.
    public var respondTime: Int64

    public init(
        book: Book,
        sourceUrl: String,
        sourceName: String,
        originOrder: Int64 = 0,
        chapterWordCount: Int = -1,
        chapterWordCountText: String? = nil,
        toc: [BookChapter]? = nil,
        respondTime: Int64 = 0
    ) {
        self.book = book
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.originOrder = originOrder
        self.chapterWordCount = chapterWordCount
        self.chapterWordCountText = chapterWordCountText
        self.toc = toc
        self.respondTime = respondTime
    }

    /// The key of the user score of the book (upstream `SourceConfig`).
    public var scoreKey: String {
        "\(sourceUrl)_\(book.name)_\(book.author)"
    }
}

/// The change-source service.
public enum ChangeSourceService {

    /// The maximum number of chapters cached over all the sources (the
    /// upstream `tocMapChapterCount` limit).
    public static let maxCachedChapters = 30_000

    /// The enabled sources, ordered by their custom order, optionally
    /// filtered by a group (the upstream `allEnabledPart` /
    /// `getEnabledPartByGroup`).
    public static func sources(
        _ all: [BookSource],
        group: String? = nil
    ) -> [BookSource] {
        let enabled = all
            .filter { $0.enabled }
            .sorted { $0.customOrder < $1.customOrder }
        guard let group, !group.isEmpty else { return enabled }
        // The upstream matches the group on the comma boundaries. An empty
        // group falls back to all the enabled sources; a group that matches
        // nothing stays empty.
        return enabled.filter { source in
            let groups = source.bookSourceGroup ?? ""
            if groups.isEmpty { return false }
            return groups
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(group)
        }
    }

    /// The sanitised author of a book (the upstream `authorRegex`).
    public static func sanitizedAuthor(_ author: String) -> String {
        var result = author
        // `^\s*作\s*者[:：\s]+`
        if let range = result.range(of: "^\\s*作\\s*者[:：\\s]+", options: .regularExpression) {
            result.removeSubrange(range)
        }
        // `\s+著`
        if let range = result.range(of: "\\s+著", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Searches the sources for the book.
    ///
    /// - Parameters:
    ///   - book: the book that is on the shelf.
    ///   - sources: the sources to search.
    ///   - options: the options of the search.
    ///   - dependencies: the network dependencies.
    public static func search(
        book: Book,
        sources: [BookSource],
        options: ChangeSourceOptions = ChangeSourceOptions(),
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> [ChangeSourceCandidate] {
        let name = book.name
        let author = sanitizedAuthor(book.author)
        var candidates: [ChangeSourceCandidate] = []
        var cachedChapters = 0

        for source in sources {
            let start = Date()
            do {
                let results = try await WebBook.searchBook(
                    bookSource: source,
                    key: name,
                    filter: { fName, fAuthor in
                        fName == name && (!options.checkAuthor || fAuthor.contains(author))
                    },
                    dependencies: dependencies
                )
                guard let hit = results.first else { continue }
                var candidate = ChangeSourceCandidate(
                    book: hit.toBook(),
                    sourceUrl: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    originOrder: source.customOrder,
                    respondTime: Int64(Date().timeIntervalSince(start) * 1000)
                )
                if options.loadInfo || options.loadToc || options.loadWordCount {
                    candidate.book = try await WebBook.getBookInfo(
                        bookSource: source,
                        book: candidate.book,
                        dependencies: dependencies
                    )
                }
                if options.loadToc || options.loadWordCount {
                    let result = try await WebBook.getChapterList(
                        bookSource: source,
                        book: candidate.book,
                        dependencies: dependencies
                    )
                    candidate.book = result.book
                    if cachedChapters < maxCachedChapters {
                        cachedChapters += result.chapters.count
                        candidate.toc = result.chapters
                    }
                }
                if options.loadWordCount, let toc = candidate.toc, !toc.isEmpty {
                    let measurement = await measureWordCount(
                        source: source,
                        book: candidate.book,
                        chapters: toc,
                        dependencies: dependencies
                    )
                    candidate.chapterWordCount = measurement.count
                    candidate.chapterWordCountText = measurement.text
                }
                candidates.append(candidate)
            } catch {
                // A broken source is skipped (the upstream swallows every
                // throwable of a source).
                continue
            }
        }
        return sorted(candidates, options: options)
    }

    /// The measurement of one chapter (the upstream `loadBookWordCount`).
    public static func measureWordCount(
        source: BookSource,
        book: Book,
        chapters: [BookChapter],
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> (count: Int, text: String) {
        guard let chapter = chapters.last else { return (-1, "") }
        let index = chapters.count - 1
        var title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 20 {
            title = String(title.prefix(20)) + "…"
        }
        do {
            let content = try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                dependencies: dependencies
            )
            let count = content.count
            return (count, "[\(index + 1)] \(title)\n字数：\(count)")
        } catch {
            return (-1, "[\(index + 1)] \(title)\n获取字数失败：\(error.localizedDescription)")
        }
    }

    /// The ranking of the candidates (the upstream comparators).
    public static func sorted(
        _ candidates: [ChangeSourceCandidate],
        options: ChangeSourceOptions = ChangeSourceOptions()
    ) -> [ChangeSourceCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsBook = options.bookScores[lhs.scoreKey] ?? 0
            let rhsBook = options.bookScores[rhs.scoreKey] ?? 0
            if lhsBook != rhsBook { return lhsBook > rhsBook }
            let lhsSource = options.sourceScores[lhs.sourceUrl] ?? 0
            let rhsSource = options.sourceScores[rhs.sourceUrl] ?? 0
            if lhsSource != rhsSource { return lhsSource > rhsSource }
            if options.loadWordCount {
                let lhsLong = lhs.chapterWordCount > 1000
                let rhsLong = rhs.chapterWordCount > 1000
                if lhsLong != rhsLong { return lhsLong }
                let lhsNumber = chapterNumber(lhs.chapterWordCountText)
                let rhsNumber = chapterNumber(rhs.chapterWordCountText)
                if lhsNumber != rhsNumber { return lhsNumber > rhsNumber }
                if lhs.chapterWordCount != rhs.chapterWordCount {
                    return lhs.chapterWordCount > rhs.chapterWordCount
                }
            }
            return lhs.originOrder < rhs.originOrder
        }
    }

    /// The chapter number of a measurement text (`[N] title`).
    public static func chapterNumber(_ text: String?) -> Int {
        guard let text else { return -1 }
        guard let range = text.range(of: "^\\[(\\d+)]", options: .regularExpression) else { return -1 }
        let digits = text[range].dropFirst().dropLast()
        return Int(digits) ?? -1
    }

    /// Switches the book to the new source.
    ///
    /// The upstream `Book.migrateTo(newBook, toc)` copies the user fields and
    /// the reading progress onto the new book; the chapter list is replaced
    /// by the caller.
    public static func switchSource(
        oldBook: Book,
        newBook: Book,
        toc: [BookChapter]? = nil
    ) -> Book {
        var book = newBook
        let chapters = toc ?? []
        let index = ChapterProgressMapper.durChapter(
            oldIndex: Int(oldBook.durChapterIndex),
            oldTitle: oldBook.durChapterTitle,
            newToc: chapters,
            oldCount: Int(oldBook.totalChapterNum)
        )
        book.durChapterIndex = Int64(index)
        if chapters.indices.contains(index) {
            book.durChapterTitle = chapters[index].title
        }
        book.durChapterPos = oldBook.durChapterPos
        book.durChapterTime = oldBook.durChapterTime
        book.group = oldBook.group
        book.order = oldBook.order
        book.customCoverUrl = oldBook.customCoverUrl
        book.customIntro = oldBook.customIntro
        book.customTag = oldBook.customTag
        book.canUpdate = oldBook.canUpdate
        book.readConfig = oldBook.readConfig
        // The upstream removes the "update error" flag.
        book.type = book.type & ~BookType.updateError
        return book
    }

    /// The automatic change of the source — upstream
    /// `ReadBookViewModel.autoChangeSource` (`ReadBookViewModel.kt:293-327`).
    ///
    /// The upstream searches every enabled text source for the book, loads
    /// the detail page when the chapter URL is missing, loads the chapter
    /// list and reads the content of the current chapter; the first source
    /// that works wins.
    public static func autoChangeSource(
        book: Book,
        sources: [BookSource],
        chapterIndex: Int = 0,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> ChangeSourceCandidate? {
        for source in sources {
            do {
                var candidate = try await WebBook.preciseSearch(
                    bookSource: source,
                    name: book.name,
                    author: book.author,
                    dependencies: dependencies
                )
                if candidate.tocUrl.isEmpty {
                    candidate = try await WebBook.getBookInfo(
                        bookSource: source,
                        book: candidate,
                        dependencies: dependencies
                    )
                }
                let result = try await WebBook.getChapterList(
                    bookSource: source,
                    book: candidate,
                    dependencies: dependencies
                )
                let toc = result.chapters
                guard !toc.isEmpty else { continue }
                // The upstream reads the content of the current chapter to
                // make sure that the source really works.
                let index = min(max(0, chapterIndex), toc.count - 1)
                let chapter = toc[index]
                let next = toc.indices.contains(index + 1) ? toc[index + 1] : toc[0]
                _ = try await WebBook.getContent(
                    bookSource: source,
                    book: result.book,
                    bookChapter: chapter,
                    nextChapterUrl: next.url,
                    dependencies: dependencies
                )
                return ChangeSourceCandidate(
                    book: result.book,
                    sourceUrl: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    originOrder: source.customOrder,
                    chapterWordCount: -1,
                    toc: toc
                )
            } catch {
                // A broken source is skipped (the upstream swallows every
                // throwable of a source).
                continue
            }
        }
        return nil
    }
}

/// The mapping of the reading progress onto a new chapter list.
///
/// Upstream `BookHelp.getDurChapter` (BookHelp.kt:499-546).
public enum ChapterProgressMapper {

    /// The similarity threshold above which the chapter names are considered
    /// equal.
    public static let nameSimilarityThreshold = 0.96

    /// The half width of the search window around the estimated chapter.
    public static let searchWindow = 10

    /// Maps the old chapter index onto the new chapter list.
    public static func durChapter(
        oldIndex: Int,
        oldTitle: String?,
        newToc: [BookChapter],
        oldCount: Int = 0
    ) -> Int {
        if oldIndex <= 0 { return 0 }
        if newToc.isEmpty { return oldIndex }
        let oldNumber = chapterNumber(oldTitle)
        let oldName = pureChapterName(oldTitle)
        let newSize = newToc.count
        let durIndex = oldCount == 0 ? oldIndex : oldIndex * oldCount / newSize
        let lower = max(0, min(oldIndex, durIndex) - searchWindow)
        let upper = min(newSize - 1, max(oldIndex, durIndex) + searchWindow)

        var nameSimilarity = 0.0
        var newIndex = 0
        var newNumber = 0
        // The Kotlin upstream iterates over an empty range when the window is
        // inverted, so the loop has to be guarded.
        let window = lower <= upper ? lower...upper : nil
        if !oldName.isEmpty, let window {
            for i in window {
                let similarity = jaccardSimilarity(oldName, pureChapterName(newToc[i].title))
                if similarity > nameSimilarity {
                    nameSimilarity = similarity
                    newIndex = i
                }
            }
        }
        if nameSimilarity < nameSimilarityThreshold && oldNumber > 0, let window {
            for i in window {
                let number = chapterNumber(newToc[i].title)
                if number == oldNumber {
                    newNumber = number
                    newIndex = i
                    break
                } else if abs(number - oldNumber) < abs(newNumber - oldNumber) {
                    newNumber = number
                    newIndex = i
                }
            }
        }
        if nameSimilarity > nameSimilarityThreshold || abs(newNumber - oldNumber) < 1 {
            return newIndex
        }
        return min(max(0, newToc.count - 1), oldIndex)
    }

    /// The number of a chapter name (`第十二章` → 12, `12. xxx` → 12).
    public static func chapterNumber(_ name: String?) -> Int {
        guard let name else { return -1 }
        let text = fullToHalf(name).replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        let pattern1 = ".*?第([\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)[章节篇回集话]"
        let pattern2 = "^(?:[\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[,:、])*([\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)(?:[,:、]|\\.[^\\d])"
        for pattern in [pattern1, pattern2] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { continue }
            let numberRange = match.range(at: 1)
            guard let swiftRange = Range(numberRange, in: text) else { continue }
            return parseChineseNumber(String(text[swiftRange]))
        }
        return -1
    }

    /// The "pure" chapter name (the number and the decoration removed).
    public static func pureChapterName(_ name: String?) -> String {
        guard let name else { return "" }
        var text = fullToHalf(name)
        text = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        // The chapter number, e.g. "第十二章 xxx".
        text = text.replacingOccurrences(
            of: "^.*?第(?:[\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)[章节篇回集话](?!$)|^(?:[\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[,:、])*(?:[\\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)(?:[,:、](?!$)|\\.(?=[^\\d]))",
            with: "",
            options: .regularExpression
        )
        // The decoration in brackets.
        //
        // The upstream uses the regular expression
        //   (?!^)(?:[open][^openclose]+)?[close]$|^[open](?:[^openclose]+[close])?(?!$)
        // but ICU REJECTS that pattern, and `replacingOccurrences` silently
        // ignores an invalid pattern on Linux (it removes the whole string),
        // so the same rule is implemented with plain Swift here.
        text = stripBrackets(text)
        // Everything that is not a letter, a digit or a CJK character.
        text = text.replacingOccurrences(
            of: "[^\\w\\u4E00-\\u9FEF〇\\u3400-\\u4DBF\\u20000-\\u2A6DF\\u2A700-\\u2EBEF]",
            with: "",
            options: .regularExpression
        )
        return text
    }

    /// The opening brackets of the upstream `regexC`.
    public static let openingBrackets: Set<Character> = ["〖", "【", "《", "〔", "[", "{", "("]
    /// The closing brackets of the upstream `regexC`.
    public static let closingBrackets: Set<Character> = ["〕", "》", "】", "〗", "]", "}", ")"]

    /// Removes the bracket decoration of a chapter name (the upstream
    /// `regexC`).
    ///
    /// The upstream removes a bracket group at the END of the name (as long as
    /// it does not start the whole name) and a bracket group at the START (as
    /// long as it does not end the whole name).
    public static func stripBrackets(_ text: String) -> String {
        var result = text
        // The trailing group.
        if let last = result.last, closingBrackets.contains(last) {
            let closeIndex = result.index(before: result.endIndex)
            var groupStart: String.Index?
            if let openIndex = result.lastIndex(where: { openingBrackets.contains($0) }) {
                let between = result[result.index(after: openIndex)..<closeIndex]
                if !between.contains(where: {
                    openingBrackets.contains($0) || closingBrackets.contains($0)
                }) {
                    groupStart = openIndex
                }
            }
            if let groupStart {
                // The match must not start the whole name.
                if groupStart != result.startIndex {
                    result = String(result[..<groupStart])
                }
            } else if closeIndex != result.startIndex {
                // A lone closing bracket.
                result = String(result[..<closeIndex])
            }
        }
        // The leading group.
        if let first = result.first, openingBrackets.contains(first) {
            var groupEnd: String.Index?
            if let closeIndex = result.firstIndex(where: { closingBrackets.contains($0) }) {
                let between = result[result.index(after: result.startIndex)..<closeIndex]
                if !between.contains(where: {
                    openingBrackets.contains($0) || closingBrackets.contains($0)
                }) {
                    groupEnd = closeIndex
                }
            }
            if let groupEnd {
                // The match must not end the whole name.
                let after = result.index(after: groupEnd)
                if after != result.endIndex {
                    result = String(result[after...])
                }
            }
        }
        return result
    }

    /// The Jaccard similarity of two strings (the upstream
    /// `JaccardSimilarity`).
    public static func jaccardSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.map { $0 })
        let right = Set(rhs.map { $0 })
        if left.isEmpty && right.isEmpty { return 1 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// The full width characters are converted to half width ones (the
    /// upstream `StringUtils.fullToHalf`).
    ///
    /// The upstream maps the ideographic space (U+3000) and the no-break space
    /// (U+00A0) to a plain space and subtracts 0xFEE0 from the other full width
    /// forms; subtracting 0xFEE0 from U+3000 would underflow.
    public static func fullToHalf(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3000, 0x00A0:
                result.append(" ")
            case 0xFF01...0xFF5E:
                result.unicodeScalars.append(UnicodeScalar(scalar.value - 0xFEE0) ?? scalar)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Parses a Chinese numeral (`十二` → 12).
    public static func parseChineseNumber(_ text: String) -> Int {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "壹": 1, "二": 2, "贰": 2, "两": 2, "三": 3, "叁": 3,
            "四": 4, "肆": 4, "五": 5, "伍": 5, "六": 6, "陆": 6, "七": 7, "柒": 7,
            "八": 8, "捌": 8, "九": 9, "玖": 9
        ]
        let units: [Character: Int] = [
            "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000,
            "万": 10_000, "萬": 10_000
        ]
        var total = 0
        var section = 0
        var number = 0
        for character in text {
            if let digit = digits[character] {
                number = digit
            } else if let unit = units[character] {
                if number == 0 { number = 1 }
                section += number * unit
                number = 0
            }
            if character == "万" || character == "萬" {
                total += section
                section = 0
            }
        }
        total += section + number
        return total
    }
}
