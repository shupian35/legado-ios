//
//  LegadoSmokeTest.swift
//  LegadoApp
//
//  The headless smoke test.
//
//  SwiftUI only exists on Apple platforms, so on this Linux/Windows host the
//  `LegadoApp` executable cannot open a window: it is compiled against the
//  `LegadoUIShim`, whose `App.main()` has no run loop. To still prove that the
//  whole port works end to end (the database, the schema, the sources, the
//  bookshelf, the reader and the local HTTP API), the executable runs this
//  smoke test instead when it is not built for an Apple platform.
//
//  Usage:  swift run LegadoApp --smoke
//
//

#if !canImport(SwiftUI)

import Foundation
import LegadoCore
import LegadoServer
import LegadoUI
import LegadoUIShim

/// Runs the whole stack once and prints a report.
enum LegadoSmokeTest {

    static func run(arguments: [String]) {
        _ = arguments.contains("--verbose") || arguments.contains("-v")
        print("Legado iOS port — headless smoke test")
        print("=====================================")

        // 1. The database.
        let store = LegadoStore(tables: MemoryTableStore())
        do {
            try store.createSchema()
            print("[ok]   schema created (\(LegadoSchema.tables.count) tables)")
        } catch {
            print("[FAIL] schema: \(error)")
            return
        }

        // 2. The seeded groups (upstream `AppDatabase.onCreate`).
        do {
            let groups = try store.visibleGroups()
            print("[ok]   default groups: \(groups.map(\.groupName).joined(separator: ", "))")
        } catch {
            print("[FAIL] groups: \(error)")
            return
        }

        // 3. A book source.
        let sourceJson = """
        {
          "bookSourceUrl": "https://example.com",
          "bookSourceName": "示例书源",
          "enabled": true,
          "searchUrl": "https://example.com/search?key={{key}}",
          "ruleSearch": "{\\"bookList\\":\\"class.book\\"}"
        }
        """
        let environment = AppEnvironment(
            store: store,
            settings: AppSettings(store: InMemorySettingsStore())
        )
        do {
            let count = try environment.importSources(json: sourceJson)
            print("[ok]   imported \(count) book source(s)")
        } catch {
            print("[FAIL] source import: \(error)")
            return
        }

        // 4. A book on the shelf.
        var book = Book(bookUrl: "https://example.com/book/1", origin: "https://example.com")
        book.name = "测试书"
        book.author = "测试作者"
        book.tocUrl = "https://example.com/book/1/toc"
        do {
            try environment.saveToShelf(book)
            let books = try environment.books(inGroup: BookGroup.Id.all)
            print("[ok]   bookshelf holds \(books.count) book(s): \(books.map(\.name).joined(separator: ", "))")
        } catch {
            print("[FAIL] bookshelf: \(error)")
            return
        }

        // 5. The search over the bookshelf.
        do {
            let hits = try environment.bookshelf().search("测试")
            print("[ok]   bookshelf search found \(hits.count) book(s)")
        } catch {
            print("[FAIL] bookshelf search: \(error)")
            return
        }

        // 6. The reader: paginate a chapter.
        let chapter = BookChapter(
            url: "https://example.com/book/1/1",
            title: "第一章",
            isVolume: false,
            baseUrl: "https://example.com",
            bookUrl: book.bookUrl,
            index: 0
        )
        do {
            try store.insert([chapter])
            let text = String(repeating: "这是一段测试文本。", count: 200)
            let provider = StaticChapterContentProvider(text: text)
            let config = ReaderConfig()
            let measurer = ApproximateTextMeasurer()
            let layout = ReaderLayout(
                config: config,
                size: CGSizeLike(width: 400, height: 700),
                measurer: measurer
            )
            let result = awaitBlocking {
                try await ChapterProvider.textChapter(
                    book: book,
                    chapter: chapter,
                    chaptersSize: 1,
                    contentProvider: provider,
                    config: config,
                    layout: layout,
                    measurer: measurer
                )
            }
            switch result {
            case .success(let textChapter):
                print("[ok]   reader laid out \(textChapter.pageSize) page(s) for \(text.count) characters")
            case .failure(let error):
                print("[FAIL] reader: \(error)")
            }
        } catch {
            print("[FAIL] reader: \(error)")
            return
        }

        // 7. The local HTTP API.
        let server = LegadoServer(configuration: LegadoAPIConfiguration(token: "smoke"))
        do {
            let port = try server.start()
            var ready = false
            for _ in 0..<50 {
                if server.status.isRunning { ready = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if ready {
                let response = server.respond(to: HTTPRequestHead(
                    method: "GET",
                    target: "/getBookshelf",
                    headers: ["Authorization": "Bearer smoke"]
                ))
                let body = String(decoding: response.body, as: UTF8.self)
                print("[ok]   local API answered \(response.code) on port \(port) (\(body.count) bytes)")

                // The upstream web clients are served by the same server: the
                // legacy navigation page at `/` and the Vue bookshelf under
                // `/vue/`.
                let legacy = server.respond(to: HTTPRequestHead(method: "GET", target: "/", headers: [:]))
                let legacyBody = String(decoding: legacy.body, as: UTF8.self)
                if legacy.code == 200 && legacyBody.contains("vue/index.html") {
                    print("[ok]   legacy web page served (\(legacyBody.count) bytes)")
                } else {
                    print("[FAIL] legacy web page: \(legacy.code)")
                }
                let web = server.respond(to: HTTPRequestHead(method: "GET", target: "/vue/", headers: [:]))
                let webBody = String(decoding: web.body, as: UTF8.self)
                if web.code == 200 && webBody.contains("id=\"app\"") {
                    print("[ok]   web bookshelf served (\(webBody.count) bytes)")
                } else {
                    print("[FAIL] web bookshelf: \(web.code)")
                }

                // The WebSocket API listens on the HTTP port + 1, like the
                // upstream web client expects.
                let socketPort = server.status.webSocketPort
                if socketPort == port + 1 {
                    print("[ok]   websocket API port \(socketPort) (= http + 1)")
                } else {
                    print("[FAIL] websocket API port \(socketPort)")
                }
                server.stop()
            } else {
                print("[FAIL] local API did not start")
            }
        } catch {
            print("[FAIL] local API: \(error)")
        }

        print("=====================================")
        print("The UI itself needs an Apple platform: the Linux build only type-checks")
        print("the SwiftUI sources against LegadoUIShim.")
    }
}

/// A chapter provider that returns a fixed text.
private final class StaticChapterContentProvider: ChapterContentProviding {
    private let text: String

    init(text: String) {
        self.text = text
    }

    func chapterContent(book: Book, chapter: BookChapter) async throws -> String? {
        text
    }
}

/// Runs an asynchronous operation from the synchronous entry point.
private final class ResultBox<T> {
    var result: Result<T, Error>?
}

private func awaitBlocking<T>(_ operation: @escaping () async throws -> T) -> Result<T, Error> {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            box.result = .success(try await operation())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return box.result ?? .failure(SmokeTestError.noResult)
}

private enum SmokeTestError: Error {
    case noResult
}

#endif
