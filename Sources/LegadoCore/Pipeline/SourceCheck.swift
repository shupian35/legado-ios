//
//  SourceCheck.swift
//  LegadoCore
//
//  The source verification (校验).
//
//  Upstream `service/CheckSourceService.kt` (261 lines) + `model/CheckSource.kt`:
//
//  * the search URL is requested with a test keyword (`我的` by default, or
//    the `checkKeyWord` of the search rule); an empty result marks the
//    source with the group "搜索失效";
//  * the explore URL is requested; an empty result marks it with "发现失效";
//  * the detail page, the chapter list and the content of the first chapter
//    are checked;
//  * a failure is stored as a Chinese group name on the source and as a
//    "// Error: …" comment; a success is reported as "校验成功".
//
//  The port keeps the exact group names and the messages so that a source
//  verified by the Android app means the same thing in the iOS app.
//

import Foundation

/// The options of the verification (upstream `CheckSource`).
public struct SourceCheckOptions: Equatable, Sendable {
    /// Whether the search URL is checked.
    public var checkSearch: Bool
    /// Whether the explore URL is checked.
    public var checkDiscovery: Bool
    /// Whether the detail page is checked.
    public var checkInfo: Bool
    /// Whether the chapter list is checked.
    public var checkCategory: Bool
    /// Whether the content is checked.
    public var checkContent: Bool
    /// The keyword of the search check.
    public var keyword: String
    /// The timeout of one source in seconds.
    public var timeout: TimeInterval

    public init(
        checkSearch: Bool = true,
        checkDiscovery: Bool = true,
        checkInfo: Bool = true,
        checkCategory: Bool = true,
        checkContent: Bool = true,
        keyword: String = "我的",
        timeout: TimeInterval = 180
    ) {
        self.checkSearch = checkSearch
        self.checkDiscovery = checkDiscovery
        self.checkInfo = checkInfo
        self.checkCategory = checkCategory
        self.checkContent = checkContent
        self.keyword = keyword
        self.timeout = timeout
    }
}

/// The result of the verification of one source.
public struct SourceCheckResult: Equatable, Sendable {
    /// The URL of the checked source.
    public var sourceUrl: String
    /// Whether the source passed.
    public var isSuccess: Bool
    /// The invalid group names (the upstream `getInvalidGroupNames`).
    public var invalidGroups: [String]
    /// The final message ("校验成功" or "校验失败:<message>").
    public var message: String
    /// The response time in milliseconds.
    public var respondTime: Int64
    /// The source after the check (the groups and the comment changed).
    public var source: BookSource

    public init(
        sourceUrl: String,
        isSuccess: Bool,
        invalidGroups: [String],
        message: String,
        respondTime: Int64,
        source: BookSource
    ) {
        self.sourceUrl = sourceUrl
        self.isSuccess = isSuccess
        self.invalidGroups = invalidGroups
        self.message = message
        self.respondTime = respondTime
        self.source = source
    }
}

/// The source verification.
public enum SourceChecker {

    /// The group names the upstream uses.
    public enum Group {
        public static let emptySearchUrl = "搜索链接规则为空"
        public static let searchFailed = "搜索失效"
        public static let emptyExploreUrl = "发现规则为空"
        public static let exploreFailed = "发现失效"
        public static let timeout = "校验超时"
        public static let scriptFailed = "js失效"
        public static let siteFailed = "网站失效"

        /// The content group of one path ("搜索正文失效" / "发现正文失效").
        public static func contentFailed(_ bookType: String) -> String { "\(bookType)正文失效" }
        /// The chapter list group of one path.
        public static func tocFailed(_ bookType: String) -> String { "\(bookType)目录失效" }
    }

    /// The success message.
    public static let successMessage = "校验成功"

    /// The failure message.
    public static func failureMessage(_ reason: String) -> String { "校验失败:\(reason)" }

    /// Checks one source.
    public static func check(
        source: BookSource,
        options: SourceCheckOptions = SourceCheckOptions(),
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> SourceCheckResult {
        var source = source
        let start = Date()
        source.removeInvalidGroups()
        source.removeErrorComment()

        do {
            if options.checkSearch {
                let keyword = checkKeyword(source, options: options)
                if let searchUrl = source.searchUrl, !searchUrl.isBlank {
                    source.removeGroup(Group.emptySearchUrl)
                    let books = try await WebBook.searchBook(
                        bookSource: source,
                        key: keyword,
                        dependencies: dependencies
                    )
                    if books.isEmpty {
                        source.addGroup(Group.searchFailed)
                    } else {
                        source.removeGroup(Group.searchFailed)
                        try await checkBook(
                            books.first!.toBook(),
                            source: &source,
                            bookType: "搜索",
                            options: options,
                            dependencies: dependencies
                        )
                    }
                } else {
                    source.addGroup(Group.emptySearchUrl)
                }
            }
            if options.checkDiscovery, let exploreUrl = source.exploreUrl, !exploreUrl.isBlank {
                let url = exploreCategories(source).first { !$0.url.isEmpty }?.url
                if let url, !url.isEmpty {
                    source.removeGroup(Group.emptyExploreUrl)
                    let books = try await WebBook.exploreBook(
                        bookSource: source,
                        url: url,
                        dependencies: dependencies
                    )
                    if books.isEmpty {
                        source.addGroup(Group.exploreFailed)
                    } else {
                        source.removeGroup(Group.exploreFailed)
                        try await checkBook(
                            books.first!.toBook(),
                            source: &source,
                            bookType: "发现",
                            options: options,
                            dependencies: dependencies
                        )
                    }
                } else {
                    source.addGroup(Group.emptyExploreUrl)
                }
            }
            let invalid = source.invalidGroupNames
            if !invalid.isEmpty {
                // The upstream joins the invalid group names with ", "
                // (Kotlin's `joinToString` default separator).
                throw SourceCheckFailure(reason: invalid.joined(separator: ", "))
            }
            let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
            return SourceCheckResult(
                sourceUrl: source.bookSourceUrl,
                isSuccess: true,
                invalidGroups: [],
                message: successMessage,
                respondTime: elapsed,
                source: source
            )
        } catch {
            let reason = error.localizedDescription
            let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
            if let failure = error as? SourceCheckFailure {
                source.addErrorComment(failure.reason)
                return SourceCheckResult(
                    sourceUrl: source.bookSourceUrl,
                    isSuccess: false,
                    invalidGroups: source.invalidGroupNames,
                    message: failureMessage(failure.reason),
                    respondTime: elapsed,
                    source: source
                )
            }
            if error is CancellationError {
                source.addGroup(Group.timeout)
                source.addErrorComment(reason)
                return SourceCheckResult(
                    sourceUrl: source.bookSourceUrl,
                    isSuccess: false,
                    invalidGroups: source.invalidGroupNames,
                    message: failureMessage(Group.timeout),
                    respondTime: elapsed,
                    source: source
                )
            }
            // A script error or a network error.
            let group = isScriptError(error) ? Group.scriptFailed : Group.siteFailed
            source.addGroup(group)
            source.addErrorComment(reason)
            return SourceCheckResult(
                sourceUrl: source.bookSourceUrl,
                isSuccess: false,
                invalidGroups: source.invalidGroupNames,
                message: failureMessage(reason),
                respondTime: elapsed,
                source: source
            )
        }
    }

    /// The keyword of the search check (the upstream `getCheckKeyword`).
    public static func checkKeyword(
        _ source: BookSource,
        options: SourceCheckOptions = SourceCheckOptions()
    ) -> String {
        if let keyword = source.searchRule?.checkKeyWord, !keyword.isBlank {
            return keyword
        }
        return options.keyword
    }

    /// The explore categories of a source.
    ///
    /// Upstream `BookSource.exploreKinds()` reads the `exploreUrl` field: it is
    /// either a JSON array of `ExploreKind` objects or a list of `分类::网址`
    /// pairs separated by `(&&|\n)+`.
    public static func exploreCategories(_ source: BookSource) -> [(name: String, url: String)] {
        ExploreKinds.parse(source.exploreUrl).map { kind in
            (name: kind.title, url: kind.url ?? "")
        }
    }

    /// Checks the detail page, the chapter list and the content of a book.
    private static func checkBook(
        _ book: Book,
        source: inout BookSource,
        bookType: String,
        options: SourceCheckOptions,
        dependencies: AnalyzeUrlDependencies
    ) async throws {
        guard options.checkInfo else { return }
        var book = book
        if book.tocUrl.isBlank {
            book = try await WebBook.getBookInfo(
                bookSource: source,
                book: book,
                dependencies: dependencies
            )
        }
        guard options.checkCategory, source.bookSourceType != BookSourceType.file else { return }
        let result = try await WebBook.getChapterList(
            bookSource: source,
            book: book,
            dependencies: dependencies
        )
        // The upstream checks the first two chapters and skips the volumes.
        let chapters = result.chapters
            .filter { !($0.isVolume && $0.url.hasPrefix($0.title)) }
            .prefix(2)
        guard let first = chapters.first else {
            source.addGroup(Group.tocFailed(bookType))
            return
        }
        guard options.checkContent else { return }
        let nextUrl = chapters.count > 1 ? chapters[chapters.index(after: chapters.startIndex)].url : first.url
        do {
            _ = try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: first,
                nextChapterUrl: nextUrl,
                dependencies: dependencies
            )
            source.removeGroup(Group.contentFailed(bookType))
            source.removeGroup(Group.tocFailed(bookType))
        } catch PipelineError.contentEmpty {
            source.addGroup(Group.contentFailed(bookType))
        } catch PipelineError.tocEmpty {
            source.addGroup(Group.tocFailed(bookType))
        }
    }

    /// Whether the error is a script error (the upstream `ScriptException`).
    private static func isScriptError(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("ScriptException") || text.contains("WrappedException")
    }
}

/// The failure of a source check (the upstream `NoStackTraceException`).
public struct SourceCheckFailure: Error, Equatable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

extension BookSource {
    /// The "// Error: …" comment of the source (the upstream
    /// `addErrorComment`).
    public mutating func addErrorComment(_ message: String) {
        let comment = bookSourceComment ?? ""
        bookSourceComment = "// Error: \(message)\n\n\(comment)"
    }

    /// Removes the error comment (the upstream `removeErrorComment`).
    public mutating func removeErrorComment() {
        guard let comment = bookSourceComment else { return }
        let lines = comment.components(separatedBy: .newlines)
        let kept = lines.filter { !$0.hasPrefix("// Error: ") }
        bookSourceComment = kept.joined(separator: "\n")
    }
}
