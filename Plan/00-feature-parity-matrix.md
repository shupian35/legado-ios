# Legado iOS — Feature Parity Matrix

Source of truth for the port: `D:\code\vscode\legado` (Android, Kotlin).
Target: `D:\code\vscode\legado-ios` (SwiftPM package `legado-ios`).

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done

---

## 0. Platform mapping

| Android | iOS | Notes |
|---|---|---|
| Gradle multi-module (`:app`, `:modules:book`, `:modules:rhino`) | SwiftPM targets `LegadoCore`, `LegadoServer`, `LegadoApp` (+ test targets) | `modules/web` was a separate Vue app — replaced by a native SwiftUI client |
| Room (SQLite) | SQLite via `SQLite3` C API / GRDB | no schema migrations needed for a fresh install; keep the same table names for backup compatibility |
| `SharedPreferences` | `UserDefaults` + a JSON config store | `AppConfig` / `ReadBookConfig` / `ThemeConfig` become observable value types |
| OkHttp + Cronet | `URLSession` (`.ephemeral` config for cookie control) | Cronet has no iOS equivalent; `URLSession` is the platform HTTP stack |
| Rhino (JSR-223) | **JavaScriptCore** (`JSContext`) on iOS/macOS | the sandbox is re-implemented as an explicit capability allow-list instead of a class deny-list |
| jsoup + JsoupXpath | **SwiftSoup** + a hand-written XPath evaluator | `AnalyzeByJSoup` ported on top of SwiftSoup |
| `java.text.BreakIterator` | `NSLinguisticTagger` / a Swift word-breakper | long-press selection |
| Android `TextView`/`Canvas` renderer | SwiftUI `Text` placed at the layout positions (`LegadoUI/PagedReader.swift`) | the page model (`TextPage`/`TextLine`/`TextColumn`) is ported 1:1 and every line is drawn at the position the layout engine computed, like the upstream `TextPage.drawPage` |
| `MediaSessionCompat` + ExoPlayer | `AVAudioSession` + `AVPlayer` | HTTP-TTS read-aloud |
| Foreground services | background tasks / `BGProcessingTask` + live activities | downloads and caching continue in the background |
| `ContentProvider` (`readerProvider`) | `App Group` + shared SQLite (no IPC provider on iOS) | same table names so third-party tools can read the DB |
| NanoHTTPD local server | `Network.framework` (`NWListener`) | binds to the LAN, token auth added |
| `Notification` channels | `UNUserNotificationCenter` categories | download / read-aloud / web-service notifications |
| `Intent` deep links (`legado://import/...`) | Universal Links / `legado://` URL scheme | import from URL, share sheet, QR codes |
| Home-screen widgets | WidgetKit | Legado has none on Android — **not in scope** |

---

## 1. Rule engine (the core of the product)

Upstream: `app/src/main/java/io/legado/app/model/analyzeRule/`.

| Feature | Upstream file | iOS target | Status |
|---|---|---|---|
| Rule string → step list (`splitSourceRule`) | `AnalyzeRule.kt:485-519` | `Sources/LegadoCore/Rule/AnalyzeRule.swift` | [x] |
| Marker resolution (`@@`, `@CSS:`, `@XPath:`, `@Json:`, `$.`, `$[`, `/`, `:`) | `AnalyzeRule.kt:545-579` | `Rule/SourceRule.swift` | [x] |
| `@put:{…}` / `@get:{key}` variables | `AnalyzeRule.kt:408-431`, `:740-769` | `Rule/SourceRule.swift`, `Rule/AnalyzeRule.swift` | [x] |
| `$n` group references | `AnalyzeRule.kt:627-654` | `Rule/SourceRule.swift` | [x] |
| `##` regex replacement (`replaceAll` / `replaceFirst`) | `AnalyzeRule.kt:436-460` | `Rule/AnalyzeRule.swift` | [x] |
| Top-level separator scanner (`&&` `\|\|` `%%`, balanced filters) | `RuleAnalyzer.kt` (378 lines) | `Rule/RuleAnalyzer.swift` | [x] |
| `getString` / `getStringList` / `getElement` / `getElements` | `AnalyzeRule.kt:163-387` | `Rule/AnalyzeRule.swift` | [x] |
| JS binding surface (`java`, `cookie`, `cache`, `source`, `book`, `result`, …) | `AnalyzeRule.kt:774-804` | `Rule/AnalyzeRule.swift` + `Script/` | [x] (protocol + bindings) |
| CSS matcher (jsoup `select`, `text`/`html`/`ownText`/`<attr>`, index syntax `tag.div.-1:10:2`, `!` exclusion) | `AnalyzeByJSoup.kt` (524 lines) | `Matcher/CSSMatcher.swift` + `Matcher/ElementsSingle.swift` | [x] (23 tests) |
| XPath matcher (JXDocument) | `AnalyzeByXPath.kt` (155 lines) | `Matcher/XPathMatcher.swift` + `Matcher/XPath.swift` (own XPath 1.0 engine) | [x] (20 tests) |
| JSONPath matcher (jayway) | `AnalyzeByJSonPath.kt` (172 lines) | `Matcher/JSONPathMatcher.swift` + `Rule/JSONPath.swift` (own engine) | [x] (22 tests) |
| Regex matcher (staged) | `AnalyzeByRegex.kt` (60 lines) | `Matcher/RegexMatcher.swift` | [x] (10 tests) |
| JS matcher (`{{…}}` / `<js>`) | `AnalyzeRule.kt` + `modules/rhino` | `Script/JavaScriptCoreEngine.swift` (JavaScriptCore) | [x] Apple / [~] Linux stub |
| The script runtime is actually **running** in the app (the network, the files, the cookies, the cache, the source variables, the login data and the captcha) | `modules/rhino/…` + `help/JsExtensions.kt` | `Script/ScriptAdapters.swift` + `App/ScriptEngineFactory.swift` + `Script/SourceVerification.swift` | [x] (the engine is created by `AppModel.makeDefault()`; the `java` facade, the source binding and the verification are ported — 23 tests) |
| JS sandbox (class deny-list) | `modules/rhino/…/RhinoClassShutter.kt` | `Script/ScriptEngineSupport.swift` — **capability allow-list** | [x] (the `ScriptCapabilities` allow-list: the network, the file read/write inside the sandbox, the cookies, the cache and the source data; a binding the script was not granted is not exposed at all — 7 tests) |

## 2. Sources, books, chapters

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| Book source entity + rules | `data/entities/BookSource.kt`, `data/entities/rule/*` | `Model/BookSource.swift` | [x] |
| RSS source entity | `data/entities/RssSource.kt` | `Model/RssSource.swift` | [x] |
| Search / explore | `model/webBook/{WebBook,BookList}.kt` | `Pipeline/WebBook.swift`, `Pipeline/BookListAssembler.swift` | [x] |
| Book info | `model/webBook/BookInfo.kt` | `Pipeline/BookInfoAssembler.swift` | [x] |
| TOC + pagination | `model/webBook/BookChapterList.kt` | `Pipeline/BookChapterListAssembler.swift` | [x] |
| Content + next-page following | `model/webBook/BookContent.kt` | `Pipeline/BookContentAssembler.swift` | [x] |
| Replace / purify rules | `data/entities/ReplaceRule.kt`, `help/ReplaceAnalyzer.kt`, `utils/RegexExtensions.kt` | `Rule/ReplaceRuleEngine.swift`, `Model/BookReadConfig.swift`, `Storage/LegadoStore.swift` (scope queries) | [x] |
| URL templating, proxies, headers, cookies | `model/analyzeRule/AnalyzeUrl.kt` (851), `help/http/*` | `Net/AnalyzeUrl.swift`, `Net/HttpClient.swift`, `Net/CookieStore.swift`, `Net/ConcurrentRateLimiter.swift` | [x] |
| Source verification (校验) | `service/CheckSourceService.kt` (261), `model/CheckSource.kt` | `Pipeline/SourceCheck.swift` | [x] (11 tests; the search → explore → detail → TOC → content chain, the Chinese invalid-group names, the `// Error:` comment) |
| Change source (换源) | `ui/book/changesource/ChangeBookSourceViewModel.kt` (580) | `Pipeline/ChangeSource.swift` | [x] (18 tests; the name-only search, the author filter, the ranking, the progress remapping) |
| Content search (搜索正文) | `ui/book/searchContent/SearchContentViewModel.kt` (108) | `Pipeline/ContentSearch.swift` | [x] (11 tests; the cached chapters only, the case-sensitive substring, the ±20-character context) |
| Login UI / login JS | `data/entities/BaseSource.kt`, `ruleHelp.md` | `Model/SourceLogin.swift` + `LegadoUI/SourceLoginView.swift` (the form) + `LegadoUI/WebLoginView.swift` (the WKWebView login) | [x] (16 tests; the `loginUi` rows, the login script, the cached login info/header, the `java` script bridge) |
| Book update (更新目录) | `ui/main/MainViewModel.kt:149-188` (`updateToc`), `help/book/BookExtensions.kt:238` (`Book.sync`) | `Pipeline/BookUpdate.swift` + `LegadoUI/AppModel.swift` (`updateBook` / `updateAllBooks`) + `LegadoUI/BookDetailView.swift` / `LegadoUI/BookshelfView.swift` (the buttons) | [x] (9 tests; the source lookup by `book.origin`, the info refresh when the `tocUrl` is blank, the wholesale chapter replacement, the progress carried over by index, the "update failed" bit, the count comparison for the new chapters, the batch pool of 9) |

## 3. Data layer

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| Room schema (21 tables + 1 view) | `data/AppDatabase.kt`, `data/dao/*` | `Storage/LegadoStore.swift` | [x] |
| Entity models (Book, BookChapter, BookGroup, Bookmark, Cache, Cookie, …) | `data/entities/*` | `Model/*` | [x] |
| Backup / restore (ZIP of JSON files) | `help/storage/{Backup,Restore}.kt` | `Storage/Backup.swift` | [x] |
| Backup encryption (AES-ECB of `servers.json`) | `help/storage/BackupAES.kt` | `Support/AES.swift` (`BackupCipher`) | [x] |
| WebDAV sync (hand-rolled client) | `help/AppWebDav.kt`, `lib/webdav/*` | `Net/WebDav.swift`, `Storage/WebDavService.swift` | [x] |
| Search cache, TTL cache, source variables | `help/CacheManager.kt`, `data/dao/CacheDao.kt` | `Storage/LegadoStore.swift`, `Net/CookieStore.swift` | [x] |
| Book groups (bitmask) | `data/dao/BookGroupDao.kt` | `Storage/LegadoStore.swift` | [x] |
| Keyboard assists / dictionary rules / HTTP-TTS | `data/entities/*` | `Model/*` | [x] |

## 4. Reading experience

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| Page model (`TextPage`/`TextLine`/`TextColumn`) | `ui/book/read/page/entities/*` | `Reader/Model/*` | [x] |
| Pagination (StaticLayout equivalent) | `page/provider/{TextChapterLayout,TextMeasure,ZhLayout}.kt` | `Reader/Layout/*` | [x] |
| Page cursor (prev/next/nextPlus, cross-chapter) | `page/provider/TextPageFactory.kt` | `Reader/Layout/TextPageFactory.swift` | [x] |
| Page-turn delegates (cover / slide / simulation / scroll / none) | `page/delegate/*` | `Reader/PageTurn.swift` (the five styles, the drag detector, the animation duration) + `Reader/ReaderInteraction.swift` (the gesture math) + `LegadoUI/PageTurnView.swift` (the SwiftUI transitions) | [x] (11 tests; the Android `Canvas` drawing becomes the SwiftUI transitions) |
| Reader configuration (5 style slots) | `help/config/ReadBookConfig.kt` (756) | `Reader/Config/ReaderConfig.swift` + `Reader/Config/ReaderConfigStore.swift` (the persistence through the settings store) | [x] (the configuration survives a relaunch now — see §8.1) |
| Reader state machine (load/progress/preload) | `model/ReadBook.kt` (1054) | `Reader/ReadBook.swift` | [x] (the new-chapter check `upToc` included, 13 tests) |
| Nine-zone tap mapping | `AppConfig.clickAction*`, `ReadView.kt:130-140` | `Reader/ReaderInteraction.swift` (`TapZoneMapper`, `ClickAction`, `ReaderClickConfiguration`) | [x] (13 tests) |
| Text selection, copy, share | `ContentTextView.kt`, `ui/book/read/TextActionMenu.kt:213-246` | `Reader/Selection.swift` (the selection model, the word/paragraph snapping) + `LegadoUI/SelectionOverlay.swift` (the eight upstream actions — 替换 / 复制 / 书签 / 朗读 / 词典 / 搜索正文 / 浏览器 / 分享, the first five with 更多) | [x] (the long press on the page opens the overlay — see §8.5) |
| Backgrounds (colour / image / day / night / E-Ink) | `ThemeConfig`, `ReadBookConfig` | `Reader/ReaderBackground.swift` (the preset, the day/night/E-Ink resolution, the mean colour) + `Core/App/ReaderBackgroundManager.swift` (the persisted presets) + `LegadoUI/ReaderBackgroundSupport.swift` | [x] (9 tests) |
| Simplified ↔ traditional Chinese | `help/book/ContentProcessor.kt:138` | `Reader/ChineseConverter.swift` + `Reader/ChineseCharacters.swift` + `Reader/ChinesePhrases.swift` (the OpenCC tables) | [x] (11 tests; the upstream exclude list is honoured) |
| Fonts (system + bundled) | `ChapterProvider.getTypeface()` | `Reader/FontResolver.swift` + `LegadoUI/ThemeSupport.swift` + `LegadoUI/FontLoader.swift` (CoreText registration) | [x] (the family/weight/size resolution, the system typeface and the user font file, selected with `fileImporter` and stored in `fontFolder`) |
| Manga / image mode | `ui/book/manga/*` | `Reader/Manga.swift` (the page assembly, the footer percent, the colour/e-ink filters, the zoom and the tap zones) + `LegadoUI/MangaView.swift` (the image reader) | [x] (14 tests; an image book opens the manga reader when `showMangaUi` is on) |
| Read-aloud: system TTS | `service/TTSReadAloudService.kt` | `Reader/ReadAloud.swift` (`ReadAloudController` + the `SpeechSynthesizing` protocol) + `LegadoUI/ReadAloudPlatform.swift` (`AVSpeechSynthesizerEngine`, the read-aloud bar) | [x] (the state machine, the platform engine and the reader bar) |
| Read-aloud: HTTP TTS | `service/HttpReadAloudService.kt` | `Reader/ReadAloud.swift` (`HttpTts`) + `LegadoUI/ReadAloudPlatform.swift` (`HttpTtsSynthesizer`, `AVAudioTtsPlayer`) | [x] (the request, the content-type check, the raw audio playback) |

## 5. Local books, RSS, downloads

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| TXT import + TOC auto-detection | `model/localBook/TextFile.kt` (479) | `Local/TextBook.swift` | [x] |
| EPUB import | `model/localBook/EpubFile.kt` | `Local/EpubBook.swift` + `Local/EpubFile.swift` + `Local/ZipArchive.swift` | [x] |
| PDF (image only) | `model/localBook/PdfFile.kt` | `Local/PdfBook.swift` + `Local/PdfKitDocument.swift` | [x] (10 tests; PDFKit on Apple, a raw page counter elsewhere) |
| UMD import | `model/localBook/UmdFile.kt` | `Local/UmdReader.swift` + `Local/UmdFile.swift` | [x] |
| TXT TOC rules | `data/entities/TxtTocRule.kt` | `Local/TxtTocRule.swift` | [x] |
| RSS subscribe / read | `model/rss/*`, `ui/rss/*` | `Pipeline/Rss.swift` (rule + default parser, next page, article content) + `LegadoUI/RSSView.swift` (the tabs, the three article layouts, the article menu, the read records) + `LegadoUI/RssSourceManagementView.swift` (the source manager, the editor, the import preview) + `LegadoUI/RssSourceToolsViews.swift` (the import preview, the source debugger, the favourite editor) | [x] (the article pagination, the article screen, the source manager, the import preview, the source debugger and the favourite editor are all there — see §8.7) |
| RSS stars / read records / groups | `ui/rss/*`, `data/entities/RssStar.kt` | `Core/App/RssLibrary.swift` (the groups, the favourites, the read records) + `Model/Misc.swift` (RssStar/RssReadRecord) + `LegadoUI/RSSView.swift` (the group filter, the favourite toggle, the favourites list) | [x] (9 tests) |
| Downloads + cache book | `service/{DownloadService,CacheBookService}.kt`, `model/CacheBook.kt` | `Net/BookCache.swift` (chapter cache + image cache + queue/retry) | [x] |
| The cache screen (the group filter + the export options) | `ui/book/cache/CacheActivity.kt`, `res/menu/book_cache.xml` | `LegadoUI/DownloadViews.swift` (the group filter, 导出全部, the export switches 净化替换 / 自定义导出章节 / 不包含章节名 / 导出到WebDAV / 导出图片到文件夹 / 并行导出书籍, the export config 导出类型 / 导出字符集 / 导出文件名 / 导出文件夹, 日志) + `Core/Local/Export.swift` (`BookExportOptions`) | [x] (the per-book export honours the switches — see §8.7) |
| Export book (TXT/EPUB) | `service/ExportBookService.kt` (878) | `Local/Export.swift` + `Local/EpubBuilder.swift` + `Local/ZipWriter.swift` | [x] |

## 6. Integration surfaces

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| Local HTTP API (26 endpoints) | `web/HttpServer.kt`, `api/controller/*` | `Sources/LegadoServer/` (`HTTPMessage.swift`, `LegadoAPI.swift`, `LegadoAPIExtra.swift`, `JSONModels.swift`, `LegadoServer.swift`, `WebAssets.swift`) — all 26 upstream routes implemented | [x] |
| WebSocket API (3 endpoints) | `web/WebSocketServer.kt`, `web/socket/*` | `Sources/LegadoServer/WebSocket.swift` (RFC 6455 handshake + frames) + `Sources/LegadoServer/LegadoWebSocket.swift` (`/bookSourceDebug`, `/rssSourceDebug`, `/searchBook`) | [x] (the upstream protocol: a JSON payload, the streamed log lines, the closing frame) |
| Book source debug (the log stream) | `model/Debug.kt` | `Pipeline/Debug.swift` (`SourceDebugger`, the ︾ ︽ ⇒ ≡ markers, the `[mm:ss.SSS]` prefix) | [x] (8 tests) |
| Content provider | `api/ReaderProvider.kt` | `Core/Storage/AppGroup.swift` (the app group, the shared database URL) + `Core/App/SharedData.swift` (the shared library export) | [x] (4 tests; the app group is only available on Apple platforms) |
| Deep links `legado://import/…` | `ui/association/*` | `Core/App/DeepLink.swift` + `LegadoUI/DeepLinkHandler.swift` | [x] (19 tests) |
| Source import / export / share / QR | `ui/association/*` | `LegadoUI/SourceManagerView.swift` (the JSON import/export) + `LegadoUI/ShareSheet.swift` (`UIActivityViewController`) + `LegadoUI/QRCodeView.swift` (`CIQRCodeGenerator`) + `LegadoUI/QRScannerView.swift` (`AVCaptureSession`) | [x] (the share sheet, the QR **generation** and the QR **scanner** are wired — the scanner imports a source from a picture like the upstream `ScanActivity`; the scanner needs a camera, so it falls back to a text field where there is none) |
| Web bookshelf (Vue) | `modules/web` (the built bundle in `app/src/main/assets/web/vue`) | `Sources/LegadoServer/WebAssets.swift` + `Sources/LegadoServer/Resources/WebUI/` — **the upstream Vue bundle itself**, copied verbatim and embedded in the server binary | [x] (the identical web UI: the bookshelf, the reader, the source list/editor and the debug console; the API answers with the upstream `ReturnData` envelope, and the WebSocket API listens on the HTTP port + 1 like the upstream client expects) |

## 7. App shell

| Feature | Upstream | iOS target | Status |
|---|---|---|---|
| Main tabs (bookshelf / explore / RSS / mine) | `ui/main/MainActivity.kt` | `LegadoUI/RootView.swift` | [x] (the four tabs are there; the upstream `showDiscovery` / `showRSS` toggles hide the 发现 / 订阅 tabs exactly like the upstream `AppConfig`) |
| Bookshelf (list + grid styles) | `ui/main/bookshelf/*` | `LegadoUI/BookshelfView.swift` + `LegadoUI/BookshelfManageView.swift` (the batch management) + `LegadoUI/BookshelfToolsViews.swift` (the group manager, the add-by-url, the export/import) + `Core/App/Bookshelf.swift` (the group filter, the six sorts, the search) | [x] (the list style and the grid style — upstream `bookshelfLayout` 0 = the list, otherwise a grid with `bookshelfLayout + 2` columns; the covers, the unread badge, the latest chapter and the last update time are in the rows; the batch management — the multi-select, the batch update / delete / group move / change source / cache clear — is ported) |
| Book info / TOC / source switch | `ui/book/{info,toc,source,changeSource}/*` | `LegadoUI/BookDetailView.swift` + `LegadoUI/TocView.swift` + `LegadoUI/BookshelfManageView.swift` (`BookInfoMenuView`) + `LegadoUI/BookToolsViews.swift` (`ChangeSourceView`) | [x] (the change source searches the enabled sources and remaps the reading progress; the book-info menu — the metadata editor, the share, the pin, the cover, the group, the variables, the delete — and the TOC screen — the TOC regex, the long-chapter split, the reverse, the word count, the Markdown export, the bookmark tab — are ported, see §8 rows 11 and 12) |
| Reader (page rendering + the state machine) | `ui/book/read/*` | `LegadoUI/ReaderView.swift` + `LegadoUI/ReaderMenuView.swift` (the menu: the page seek, the chapter list, the read style, the read aloud, the brightness, the upstream top-bar options) + `LegadoUI/PagedReader.swift` + `LegadoUI/PageTurnView.swift` + `LegadoUI/SelectionOverlay.swift` + `LegadoUI/ReaderSearchBar.swift` + `Reader/ReadBook.swift` | [x] for the core (the state machine, the page model, the page drawing, the nine-zone taps, the drag, the system integrations) / [~] for the reader settings — see §8.5 for the honest remainder (the tip system, the style dialog, the read-aloud dialog, the continuous scroll, the manga menu) |
| Search / content search | `ui/book/{search,searchContent}/*` | `LegadoUI/DiscoverView.swift` (`SearchView`) + `LegadoUI/BookToolsViews.swift` (`ContentSearchView`) | [~] (the single-source search and the content search work; the concurrent multi-source scope search, the scope dialog, the history and the 精准搜索 toggle are being finished — see §8.4) |
| Settings (all `PreferKey`s) | `ui/config/*`, `help/config/*` | `LegadoUI/SettingsView.swift` + `LegadoUI/AdvancedSettingsView.swift` (every key editable) + `LegadoUI/MineViews.swift` (the TXT TOC rules, the dictionary rules, the read records, the HTTP TTS, the file management, the about) + `Core/App/AppSettings.swift` (the 182 upstream keys) | [~] (the port models **exactly** the 182 upstream `PreferKey` constants — `Tests/LegadoCoreTests/SettingsKeyParityTests.swift` fails if one is missing or if the port invents one — but the upstream's own config screens (`ui/config/*`) are only partly ported, see §8.2) |
| Theme (day / night / E-Ink) | `help/config/ThemeConfig.kt` | `Core/App/Theme.swift` (`AppTheme`, `ThemeMode`, `ThemeManager`, the four upstream themes) + `Core/App/ThemePreferences.swift` (`ThemeColors` — the eight upstream colour preferences, the background image and its blur radius) + `LegadoUI/ThemeSupport.swift` + `LegadoUI/ShellBackgroundView.swift` | [x] (the manager, the settings picker, the colour keys, the background image + the blur and the background colour are wired) |
| Import / export / backup UI | `ui/import`, `ui/export`, `ui/file` | `LegadoUI/SourceManagerView.swift` (the source import/export) + `LegadoUI/BackupView.swift` (the local ZIP backup, the restore, the WebDAV upload/download) | [x] (the backup screen writes the upstream ZIP into `<documents>/backup` and restores it, and it drives the WebDAV client) |
| Notifications | `App.kt:179-219`, `AppConst.kt:19-21` | `Core/App/Notifications.swift` (the three channels, the content factories, the six media actions) + `LegadoUI/Notifications.swift` (`NotificationService`, UserNotifications) + `LegadoUI/ReadAloudPlatform.swift` (the transport notification) | [x] (the three channels exist, the download / read-aloud notifications are posted and the transport notification carries the six upstream actions — 上一章 / 上一段 / 暂停 / 下一段 / 下一章 / 停止) |
| iOS bundle (Xcode project, Info.plist, URL scheme, file sharing) | `app/src/main/AndroidManifest.xml` | `project.yml` (XcodeGen) → `LegadoApp.xcodeproj`, `Sources/LegadoAppUI/Info.plist` | [x] (the project is generated; it can only be built on a Mac; the Info.plist carries the camera usage description (the QR scanner would be killed without it), the `audio` background mode (the read-aloud with the screen off), the deep-link scheme, the document types and the seven launcher icons, which `Scripts/render_launcher_icons.py` renders from the upstream vector drawables) |
| The Apple-only code paths are type-checked on Linux | — (the port's own safety net) | `Scripts/apple-stubs/` (the UIKit / AVFoundation / WebKit / MediaPlayer / CoreImage / CoreText / PDFKit / UserNotifications stubs) + `Scripts/typecheck_apple.sh` + the CI step | [x] (the `#if canImport(UIKit)` blocks are never compiled by the Linux build — the stub modules make `canImport` true, so the same sources are type-checked with the Apple branches enabled; the check has already caught 13 real iOS build errors) |
| Book source editor | `ui/book/source/edit/*` | `LegadoUI/SourceEditorView.swift` (the fields, the rules as raw JSON, the check, the login, the rule help) | [x] (the upstream edits the rules with a structured form; the port edits the rule JSON, which is how the rules are stored) |
| Replace rules / bookmarks / group management | `ui/book/replace/*`, `ui/book/manage/*`, `ui/main/bookshelf/groups/*` | `LegadoUI/ManageViews.swift` (`ReplaceRuleView` + `ReplaceRuleEditor`, `BookmarkView`, `BookGroupView`) + `LegadoUI/BookshelfToolsViews.swift` (`GroupManageView`) | [~] (the rule editor has a live test field, the groups use the first free power of two; the replace-rule toolbar (the imports, the search, the sort, the bulk actions) is being finished — see §8.3) |

---

## 8. The known gaps (the independent audits of 2026-11-03)

> **Read this section before trusting any `[x]` above.** Four read-only audits
> walked the upstream `app/src/main/java/io/legado/app/` tree (the `ui/` folder,
> the services, the receivers, the preferences XML and the manifest) and compared
> every **user-visible** feature with the port. They found that the matrix
> above was **overstated**: a preference key that exists in `AppSettings` is
> not a shipped feature unless a screen actually lets the user change it.
>
> | The audit | The upstream features checked | Present | Partial | Missing |
> |---|---|---|---|---|
> | The settings + the source management (`ui/config/*`, `ui/book/source/*`) | 189 | 28 (15 %) | 95 (50 %) | 66 (35 %) |
> | The bookshelf + the book info + the TOC + the groups (`ui/main/bookshelf/*`, `ui/book/{info,toc,manage}/*`) | 112 | 19 (17 %) | 20 (18 %) | 73 (65 %) |
> | The RSS + the discover + the search (`ui/rss/*`, `ui/book/{search,searchContent}/*`) | 120 | 15 (13 %) | 12 (10 %) | 93 (78 %) |
> | The reader (`ui/book/read/*`) | 145 | 23 (16 %) | 30 (21 %) | 92 (63 %) |
> | **Total** | **566** | **85 (15 %)** | **157 (28 %)** | **324 (57 %)** |
>
> The tables below are the gap lists the audits produced; the **state** column
> says what the port offers **today** (many rows were closed after the audit).
> The rows that are still open are the real remainder of the port — §8.6 is the
> short list of what is left (13 items, one of them a deliberate deviation).

### 8.1 The systemic causes (why so much was missing)

1. **A preference key is not a feature.** The port reproduces all 182 upstream
   `PreferKey` constants (`Tests/LegadoCoreTests/SettingsKeyParityTests.swift`
   fails if one is missing or if the port invents one) — but 88 of the 121
   upstream preferences were never *read* by any screen, and the only generic
   editor (`LegadoUI/AdvancedSettingsView.swift`) writes a **String** while
   `bool(forKey:)` only accepted a Bool ⇒ every boolean edited there read back
   as `false`. FIXED: `settingsBool(from:)` / `settingsInt(from:)` now accept the
   string forms, and the reader preferences have a real screen.
2. **The reader persisted nothing.** `ReaderConfig()` was rebuilt on every open,
   so every style preference was lost between launches. FIXED:
   `Core/Reader/Config/ReaderConfigStore.swift`.
3. **The upstream's config screens were never ported**: the upstream has no
   `AppConfigFragment` / `BookConfigFragment` / `ReadConfigFragment` — the real
   ones are `ui/config/{BackupConfigFragment, CheckSourceConfig, ConfigActivity,
   CoverConfigFragment, DirectLinkUploadConfig, OtherConfigFragment,
   ThemeConfigFragment, ThemeListDialog, WelcomeConfigFragment}.kt` plus the
   read preferences in `ui/book/read/config/MoreConfigDialog.kt:86` and
   `ReadAloudConfigDialog.kt:82`.

### 8.2 The settings + the source management (66 missing)

| The upstream feature | Upstream | The state in the port |
|---|---|---|
| The preferences with no `SettingsKey` case (`clickRegionalConfig`, `disableReturnKey`, `customPageKey`, `mediaButtonOnExit`, `systemMediaControlCompatibilityChange`, `mediaButtonPerNext`, `sysTtsConfig`, `welcomeStyle`, `coverConfig`, `themeList`, `saveDayTheme`, `saveNightTheme`, `coverRule`, `import_old`) | `app/src/main/java/io/legado/app/constant/PreferKey.kt` | **open** — the port models the 182 upstream `PreferKey` constants exactly (`SettingsKeyParityTests`), but these 14 are raw keys that the upstream code reads by hand (not constants) ⇒ they are neither modelled nor editable |
| The `CheckSourceConfig` screen (the timeout + the scope) | `ui/config/CheckSourceConfig.kt` | **closed** — `LegadoUI/SourceCheckView.swift` (`SourceCheckConfigView` + `SourceCheckConfig.load/save` — the options are persisted now) |
| The `DirectLinkUploadConfig` screen | `ui/config/DirectLinkUploadConfig.kt` | **closed** — `LegadoUI/DirectLinkUploadView.swift` + `Core/App/DirectLinkUpload.swift` (the three default rules, the compress, the test upload) |
| 清除缓存 (the app-cache clear) + the "ignore the items when restoring" dialog + the backup-directory picker | `ui/config/OtherConfigFragment.kt` | **closed** — `LegadoUI/BackupIgnoreView.swift` (`ClearCacheButton` + `BackupIgnoreConfigView`) + `Core/Storage/BackupIgnoreConfig.swift` + the picker in `LegadoUI/BackupView.swift` |
| The source management: 新建书源, 从本地文件导入, 从网络链接导入, 扫码导入, 按域名分组书源, 书源帮助, the group filters, the search box, the bulk 允许发现 / 置顶 / 置底 / 加入分组 / 导出所选, the per-row 置顶 / 允许发现, the group rename | `ui/book/source/manage/*` | **closed** — `LegadoUI/SourceManagerView.swift` (the search, the sort, 新建, the three imports — the `QRScannerView` IS instantiated now, 按域名分组, 书源帮助, the filters, the bulk actions, the per-row 置顶 / 允许发现) + the group rename in `LegadoUI/ManageSources.swift` |
| The source editor's 调试 / 搜索 / 清除Cookie / 自动补全 / 复制粘贴 / 设置变量 / 二维码分享 / 分享 / 帮助 | `ui/book/source/edit/*` | **closed** — `LegadoUI/SourceEditorView.swift` (the 更多 menu) + the new `Core/Rule/RuleComplete.swift` (`RuleAutoCompleter` — the upstream's `help/RuleComplete.kt`). The **debug screen's** 扫码 / 查看原始HTML / 刷新发现 / 帮助 are **closed too** (`LegadoUI/SourceDebugView.swift` + `Core/Pipeline/Debug.swift`) |
| The theme LIST (apply / share / delete / import) — the port only edits one theme object | `ui/config/ThemeListDialog.kt` | **closed** — `LegadoUI/ThemeListView.swift` |
| The reader's "more settings" — all 28 `pref_config_read.xml` preferences were unreachable | `ui/book/read/config/MoreConfigDialog.kt:86` | **closed** — `LegadoUI/ReaderSettingsView.swift` (`ReaderPreferencesView` + the style rows) + `Core/Reader/Config/ReaderConfigStore.swift` (the reader preferences are persisted now) |

### 8.3 The bookshelf + the book info + the TOC + the groups (73 missing)

| The upstream feature | Upstream | The state in the port |
|---|---|---|
| The TOC rows were **not tappable** — the user could not open a chapter from the table of contents | `ui/book/toc/TocActivity.kt` | **closed** — `LegadoUI/TocView.swift` (the chapter + bookmark rows are buttons, the current chapter is highlighted, the 顶部/底部 jump, the 已缓存 marker, the replace rules on the titles) |
| The book info: the cover, the built-in cover gallery, 加入/移出书架, the 来源名称, 换分组, 最新章节, 分组名, the menu (上传到远程 / 刷新 / 登录 / 复制目录链接 / 允许更新 / 删除前确认 / 清除缓存 / 日志) | `ui/book/info/BookInfoActivity.kt` (725) | **mostly closed** — `LegadoUI/BookDetailView.swift` (the cover, the source name, the latest chapter, the group, the menu, the share as `${bookUrl}#$bookJson`) |
| The bookshelf rows: the cover, 最新章节, the unread badge, 最后更新时间, the long-press → the book info | `ui/main/bookshelf/BookshelfAdapter.kt` | **closed** — `LegadoUI/BookshelfView.swift` (the badge = `max(totalChapterNum - durChapterIndex - 1, 0)`) |
| The bookshelf menu: 搜索, 添加网址, 导出书架 / 导入书架, 日志, the cache/download screen, the bookshelf config dialog, the pull-to-refresh, the per-group sort, the Chinese ordering | `ui/main/bookshelf/BaseBookshelfFragment.kt:93-122` | **closed** — the menu + the group manager + the add-by-url + the export/import (`LegadoUI/BookshelfToolsViews.swift`); the **cache/download screen** (`LegadoUI/DownloadViews.swift` — the download queue, the per-book cache / stop / export and the reader's 离线缓存 dialog); the **bookshelf config dialog** (分组样式 / 显示未读标志 / 显示上次更新时间 / 显示待更新数量 / 快速滚动 / 六列 — `LegadoUI/BookshelfConfigView.swift` + the 文件夹 group style + the fast scroll bar in `LegadoUI/BookshelfView.swift`); the **per-group sort override** (the group's 更多 → 排序 submenu + `AppModel.setGroupSort`) and the **Chinese ordering** (the upstream `String.cnCompare` = the ICU `zh_Hans_CN` collation — `Core/App/Bookshelf.swift`) |
| The bookshelf management: 反选, 选择区间, the drag reorder, the search, the group filter, the per-item delete/group, 批量换源, 允许/禁止更新, 批量清除缓存, 导出用到的书源, the delete confirmation | `ui/book/manage/BookshelfManageActivity.kt` (418) | **mostly closed** — `LegadoUI/BookshelfManageView.swift` (the search, the group filter, 全选/取消/反选, the interval check, the drag reorder, the batch actions, the delete confirmation + the "delete the local file" box) |
| The group management: the group edit (the name / the cover / the per-group sort / 启用刷新), 显示/隐藏, the drag reorder, the 64-group limit | `ui/main/bookshelf/dialog/GroupManageDialog.kt` | **closed** — `LegadoUI/BookshelfToolsViews.swift` (`GroupManageView`) + `LegadoStore.canAddGroup()` |
| The replace-rule toolbar (the group submenu, 导入本地/在线/二维码, 帮助, 启用/禁用所选, 置顶/置底, 导出所选, 搜索, 拖拽排序) | `ui/book/replace/*` | **closed** — `LegadoUI/ManageViews.swift` (the imports, the search, the sort, the bulk actions) |
| The TOC: the TOC regex as a managed rule list, the VIP lock, the 更新时间 tag | `ui/book/toc/TocActivity.kt` | **closed** — the TOC regex is now a managed rule list (`LegadoUI/TocRegexPickerView.swift` + `LegadoStore.importTxtTocRules/moveTxtTocRules/updateTxtTocRuleOrder` + `ReaderController.applyTocRegex`); the VIP lock + the 更新时间 tag are in the chapter row (`LegadoUI/TocView.swift`, the upstream `ChapterListAdapter`) |

### 8.4 The RSS + the discover + the search (93 missing)

| The upstream feature | Upstream | The state in the port |
|---|---|---|
| The article pagination — the port computed the next URL and dropped it, so only page 1 ever showed | `model/rss/RssParser.kt` + `ui/rss/ReadRssActivity.kt` | **closed** — `Core/Pipeline/Rss.swift` returns the `RssArticlePage` (the articles + the next URL) and `LegadoUI/RSSView.swift` loads the next page |
| The article WebView (enableJs / injectJs / the style / the whitelist / the blacklist / the image save / the download / the JS bridge) | `ui/rss/ReadRssActivity.kt:286-519` | **closed** — `LegadoUI/RssArticleReaderView.swift` (the WKWebView + the JavaScript bridge) |
| The RSS source manager: the imports, the search, the multi-select, the drag reorder, the groups, the delete, the filters; the editor's ~30 fields (the WEB_VIEW tab, ruleTitle / rulePubDate / ruleDescription / ruleImage / ruleLink, sortUrl / loginUrl / header / jsLib) | `ui/rss/RssSourceActivity.kt:118-380`, `RssSourceEditActivity.kt:209-276` | **mostly closed** — `LegadoUI/RssSourceManagementView.swift` (the imports, the search, the multi-select, the drag, the groups, the delete, the filters); the editor still exposes ~7 of the ~30 upstream fields |
| The favourites screen (the group tabs, the edit, the delete, the tappable rows) | `ui/rss/RssFavoritesActivity.kt:101-161` | **closed** — `LegadoUI/RssFavoritesView.swift` |
| The multi-source search (the upstream searches every enabled source concurrently), the scope dialog, the search history, 精准搜索, the "已在书架" marker, the book detail from the search result | `ui/book/search/SearchViewModel.kt:98-112` | **closed** — `LegadoUI/SearchView.swift` (the keyword, the history, the scope sheet, 精准搜索, the "已在书架" marker, the results open the book detail) |
| The discover list: the source search, the group filter, the per-source long-press menu, the pagination, the "已在书架" marker | `ui/book/explore/ExploreFragment.kt` | **closed** — `LegadoUI/DiscoverView.swift` (the source filter, the group chips, the long-press menu, the pagination) |
| The content search: the 净化/替换规则 toggle, the result counter, the jump-to-top/bottom, the stop button, the tappable rows | `ui/book/searchContent/SearchContentViewModel.kt` | **closed** — `LegadoUI/BookToolsViews.swift` |

### 8.5 The reader (92 missing)

| The upstream feature | Upstream | The state in the port |
|---|---|---|
| The text selection (the long-press → the action menu) — the `ReaderSelectionController` existed but was never triggered | `ui/book/read/TextActionMenu.kt:213-246` | **closed** — `LegadoUI/SelectionOverlay.swift` (the eight upstream actions, the first five + 更多) + the long-press in `LegadoUI/PagedReader.swift` |
| The in-reader search overlay (the count, the previous/next result, the exit) | `ui/book/read/SearchMenu.kt:109-179` | **closed** — `LegadoUI/ReaderSearchBar.swift` |
| The dictionary lookup | `data/entities/DictRule.kt:40` | **closed** — `Core/App/Dictionary.swift` + `LegadoUI/DictDialogView.swift` |
| The page-turn animation was never animated (`progress` was not bound to the drag session) | `LegadoUI/PageTurnView.swift` | **closed** — `PageTurnContainer.onProgress` |
| The reader's top-bar options (章节换源 / 模拟阅读 / 编辑内容 / 更新目录 / 启用替换净化 / 删除ruby标签 / 删除h标签 / 日志 / 反转正文 / 切换编码 / 图片样式 / 获取进度 / 覆盖进度 / 同名章节合并 / 有效替换规则 / 帮助 / 书源登录 / 章节购买) | `res/menu/book_read.xml`, `ui/book/read/ReadBookActivity.kt` | **mostly closed** — `LegadoUI/ReaderMenuView.swift` now offers 模拟阅读 / 编辑内容 / 切换编码 / 重新分段 / 删除ruby标签 / 删除h标签 / 移除相同标题 / 反转正文 / 图片样式 / 获取进度 / 覆盖进度 / 目录正则 / 夜间模式 / 朗读设置 / 有效替换规则 / 换源 / 更新目录 / 刷新本章 / 刷新后续 / 刷新全部 / 启用替换净化 / 添加书签 / 自动翻页间隔 / 搜索正文 / 离线缓存 / 日志 / 帮助, plus the source actions 登录 / 章节购买 / 编辑书源 / 禁用书源 (`Core/App/ChapterPay.swift`); the **per-chapter 章节换源** is still **open** |
| The reader style dialog (the font family, the letter spacing, the indent, the weight, the underline, the title mode, the padding, the Chinese converter, the vertical layout, the double page) | `ui/book/read/config/ReadStyleDialog.kt:110-161` | **closed** — `LegadoUI/ReaderSettingsView.swift` (`ReaderStyleRows` / `ReaderPageRows` / `ReaderColorRows` / `ReaderFontRows` / `ReaderConverterRow`) |
| The background / text colour / alpha UI and the style import-export (readConfig.zip) | `ui/book/read/config/BgTextConfigDialog.kt:129-179` | **mostly closed** — the background presets + the colours + the alpha are in `LegadoUI/ReaderMenuView.swift` (`backgroundSection`) and `Core/App/ReaderBackgroundManager.swift`; the **readConfig.zip import/export** is still **open** |
| The header / footer TIP system (14 tip types) | `ui/book/read/page/PageView.kt:157-266` | **closed** — `Core/Reader/Tips.swift` (`ReaderTipType` + `ReaderTipRenderer` + the 12 `ReaderConfig` fields) + `LegadoUI/ReaderTipView.swift` |
| The click-region editor (the nine `clickAction*` keys exist and are read, but there is no UI) | `ui/book/read/config/ClickActionConfigDialog.kt:64-134` | **closed** — `LegadoUI/ClickRegionEditorView.swift` |
| The read-aloud dialog (the rate / the timer / the engine / the start at the current page / the paragraph highlight / 按页朗读 / the streaming audio) | `ui/book/read/config/ReadAloudDialog.kt:97-163` | **closed** — `LegadoUI/ReaderAloudDialogView.swift` (the rate, 跟随系统语速, the timer, the HTTP-TTS engine, 按页朗读, the upstream `pref_config_aloud.xml` toggles), the **paragraph highlight** (`ReadBook.moveToPosition` + `TextPage.updatePageAloudSpan` + `LegadoUI/ReaderView.swift`) and the **streaming audio** (`Core/Reader/HttpTtsPlayback.swift` + the `AVPlayer` streamer in `LegadoUI/ReadAloudPlatform.swift`) |
| The continuous-scroll reading mode + the E-Ink auto page | `ui/book/read/page/delegate/ScrollPageDelegate.kt`, `page/AutoPager.kt` | **closed** — `Core/Reader/ScrollMode.swift` (the upstream `ContentTextView.scroll(mOffset)` + the `ScrollPageDelegate.calcNextPageOffset`/`calcPrevPageOffset` + the stacked pages of `ContentTextView.drawPage`) + `LegadoUI/ReaderScrollView.swift`; the **E-Ink auto page** and the upstream's normal progress mode are in `Core/Reader/AutoPager.swift` (the three modes `pageTurn` / `scroll` / `progress` + the accent progress bar) |
| The manga menu entries (the page seek bar, the chapter URL → the browser, the brightness position, the toolbar → the book info) | `ui/book/manga/MangaMenu.kt` | **closed** — `LegadoUI/MangaMenuView.swift` (换源 / 刷新 / 目录, the 禁用缩放 / 禁用点击滚动 / 自动翻页 / 自动滚动 / 横向滚动 / 禁用翻页动画 / 隐藏标题 / 电子墨水 / 灰度 toggles, 预下载数, 自动翻页速度, 页脚设置, 颜色滤镜, 电子墨水阈值, the page seek bar) + `Core/App/MangaConfig.swift` + `LegadoUI/MangaConfigViews.swift` (the colour filter, the footer, the e-ink threshold); the chapter name / address open the web page (`LegadoUI/ChapterLinkView.swift` — the upstream `ReadMenu.chapterViewClickListener`: the system browser or the built-in browser) |
| The brightness slider only changed a local `@State` — it never touched `UIScreen.main.brightness` | `ui/book/read/ReadMenu.kt:384-396` | **closed** — `LegadoUI/ReaderSystemIntegration.swift` (`setBrightness(percent:)` writes `UIScreen.main.brightness`) + the slider in `LegadoUI/ReaderMenuView.swift` |
| The volume keys | `ui/book/read/BaseReadBookActivity.kt:377-391` | **a deliberate deviation** — intercepting them needs a `UIApplication` subclass, which SwiftUI cannot install; the preference is kept and exposed |

### 8.6 What is still open (the state on 2026-11-04)

The audits found 324 missing features; the work since then closed the great
majority of them (the tables above name the file that closes each row). The
**real remainder** is this list — everything else in §8 is closed or partly
closed with the reason named in its row. Only the **deliberate deviations**
are left: they are the Android-only behaviours that have no iOS equivalent.

> The four **fresh** audits of 2026-11-04 (the reports are in `Plan/audits/`)
> re-walked the four areas and found a **second wave** of gaps that the first
> wave had missed — §8.7 lists them. They are the real work list now.

| # | The remaining gap | The upstream | Why it is not ported / where it lives |
|---|---|---|---|
| 1 | The **volume keys** — the hardware volume buttons turn the pages | `ui/book/read/BaseReadBookActivity.kt:377-391` | *Deliberate deviation* — a SwiftUI app cannot install a `UIApplication` subclass, so the volume keys are not intercepted (`LegadoUI/ReaderSystemIntegration.swift`) |
| 2 | The **custom page key** (`customPageKey`) — the user picks the hardware key codes that turn the page | `MoreConfigDialog.kt:181` → `PageKeyDialog` | *Deliberate deviation* — iOS has no hardware key codes to pick; the preference keys themselves exist (`Core/App/AppSettings.swift`) |
| 3 | The **system TTS settings** (`sysTtsConfig`) — the screen of the system's text-to-speech engine | `ReadAloudConfigDialog.kt:107` → `IntentHelp.openTTSSetting()` | *Deliberate deviation* — iOS has no equivalent system screen; the engine is configured inside the app (`LegadoUI/ReaderAloudDialogView.swift`) |
| 4 | The **media button on exit** (`mediaButtonOnExit`) — the media key wakes the app | `AppConfig.kt:467` + `MediaButtonReceiver.kt:103` | *Deliberate deviation* — the app is foreground-only on iOS; the preference exists and is honoured by `LegadoUI/MediaCommandBridge.swift` |
| 5 | The **`optimizeRender`** preference — the Android canvas recorder | `AppConfig.kt:41-42, 92-93` | *Deliberate deviation* — the API is Android-only (API 29+); the preference exists and the reader draws with SwiftUI |

**Closed since the audits** (they were in the tables above, the list is kept
here so that the remainder is easy to see):

- the **per-chapter source change** (章节换源 — the source of one chapter, not
  of the whole book: `Core/Pipeline/ChangeChapterSource.swift` +
  `LegadoUI/BookToolsViews.swift` + the reader's 章节换源 entry; the upstream
  `ChangeChapterSourceDialog` finds the matching chapter in the new table of
  contents and replaces the content of the current chapter);
- the **14 upstream raw preference keys** (`clickRegionalConfig`,
  `disableReturnKey`, `customPageKey`, `mediaButtonOnExit`,
  `systemMediaControlCompatibilityChange`, `mediaButtonPerNext`,
  `sysTtsConfig`, `welcomeStyle`, `coverConfig`, `themeList`,
  `saveDayTheme`, `saveNightTheme`, `coverRule`, `import_old`) — every
  behaviour behind them exists in the port: the click-region editor
  (`LegadoUI/ClickRegionEditorView.swift`), the disabled back key while the
  reader menu is hidden (`Core/App/AppSettings.swift` →
  `LegadoUI/ReaderView.swift`), the media-button paragraph
  (`LegadoUI/MediaCommandBridge.swift`), the **old-data import**
  (`Core/Storage/ImportOldData.swift` — the upstream `help/storage/ImportOldData.kt`
  with `myBookShelf.json` / `myBookSource.json` / `myBookReplaceRule.json` and
  the old rule syntax conversion; the UI in `LegadoUI/BackupView.swift`), the
  **cover configuration + the cover rule** (`Core/App/BookCover.swift` +
  `LegadoUI/ConfigScreens.swift`), the **welcome configuration**
  (`LegadoUI/ConfigScreens.swift`), the **saved day / night themes**
  (`Core/App/Theme.swift` → `saveCurrentTheme(name:isNightTheme:)`) and the
  **theme list** (`LegadoUI/ThemeListView.swift`); only the three
  Android-only rows of the table above stay open;
- the **continuous-scroll reading mode** (`Core/Reader/ScrollMode.swift` +
  `LegadoUI/ReaderScrollView.swift` — the upstream stacks the current + the
  next pages and the offset crosses the page boundary exactly like
  `ContentTextView.scroll(mOffset)`);
- the **E-Ink auto page** and the upstream's normal progress mode
  (`Core/Reader/AutoPager.swift` — the three modes `pageTurn` / `scroll` /
  `progress` + the accent progress bar of `AutoPager.onDraw`);
- the **read-aloud paragraph highlight** (`ReadBook.moveToPosition` +
  `TextPage.updatePageAloudSpan` + the accent colour of the read-aloud lines)
  and the **streaming HTTP-TTS audio** (`Core/Reader/HttpTtsPlayback.swift` +
  the `AVPlayer` streamer);
- the **cache / download screen** (`LegadoUI/DownloadViews.swift` —
  `DownloadManageView` is the upstream `CacheActivity`: the books with their
  download progress, the per-book 缓存 / 全部缓存 / 停止 / 导出, the toolbar
  全部缓存 / 全部停止 / 日志; the reader's 离线缓存 dialog is the upstream
  `showDownloadDialog()`), and the **TXT / EPUB export** of the cache screen
  (`LegadoAppModel.exportBook(book:format:)` → `Core/Local/Export.swift`);
- the **app log** (`Core/App/AppLog.swift` — the upstream's in-memory ring
  buffer of 100 entries — and `LegadoUI/AppLogView.swift`, the upstream
  `AppLogDialog`);
- the **reader help** (`LegadoUI/AppLogView.swift` — the upstream
  `readMenuHelp.md`);
- the **reader's source actions** (登录 / 章节购买 / 编辑书源 / 禁用书源 —
  `LegadoUI/ReaderMenuView.swift` + `Core/App/ChapterPay.swift`; the upstream's
  `contentRule.payAction` script is evaluated with the chapter as the
  context, and the `chapter` / `book` / `nextChapterUrl` script bindings of
  `AnalyzeRule.evalJS` were added to make that possible);
- the **reader's content refresh** (刷新本章 / 刷新后续 / 刷新全部 — the
  upstream `ReadBookViewModel.refreshContentDur/After/All`);
- the **source debug screen's** 扫码 / 查看原始HTML / 刷新发现 / 帮助
  (`LegadoUI/SourceDebugView.swift` — the raw HTML of every step is captured
  by `AnalyzeUrlDependencies.debugCapture` and the states 10 / 20 / 30 / 40
  are kept out of the log list, exactly like the upstream
  `BookSourceDebugModel.printLog`);
- the **bookshelf config dialog** (分组样式 / 显示未读标志 / 显示上次更新时间 /
  显示待更新数量 / 快速滚动 / 六列 — `LegadoUI/BookshelfConfigView.swift`, the
  文件夹 group style and the fast scroll bar in `LegadoUI/BookshelfView.swift`),
  the **per-group sort override** (the group's 更多 → 排序 submenu) and the
  **Chinese ordering** (the upstream `String.cnCompare` — the ICU `zh_Hans_CN`
  collation in `Core/App/Bookshelf.swift`);
- the **TOC's VIP lock** + the **更新时间 tag** (`LegadoUI/TocView.swift`);
- the **chapter name / address → the browser** (`LegadoUI/ChapterLinkView.swift`
  — the system browser or the built-in browser, the upstream
  `ReadMenu.chapterViewClickListener`);
- the **readConfig.zip import / export** of the reader style
  (`Core/Reader/Config/ReaderConfigArchive.swift` — the archive holds
  `readConfig.json` with the field names of the upstream `ReadBookConfig.Config`
  + the font + the background images, so an archive of the Android app is read
  by the port and the other way round; `LegadoUI/ReaderStyleArchiveView.swift`
  is the upstream `BgTextConfigDialog` with its 导入配置 / 导出配置);
- the **RSS source editor** — the audit row was stale: the port's
  `LegadoUI/RssSourceManagementView.swift` already has the three tabs of the
  upstream `RssSourceEditActivity` (基础 / 列表 / WEB_VIEW) with every field;
- the **reader's preference screen** — the audit found that `ReaderSettingsView`
  / `ReaderPreferencesView` / `ClickRegionEditorView` were **dead code**, so
  the whole upstream `pref_config_read.xml` (28 preferences) had no UI. It is
  now reachable from the reader's 更多设置 and from the app's 阅读设置
  (`LegadoUI/ReaderSettingsView.swift` → `ReaderPreferenceRows` +
  `Core/App/ReaderPreferences.swift` — the enums and the accessors);
- the **inline images of the reader** — the upstream splits the content on
  `AppPattern.imgPattern` and lays every image out as its own line
  (`ChapterProvider.setTypeImage`); the port now does the same
  (`Core/Reader/Images.swift` — `ChapterImageSplitter` + `ImageSizeDetector` +
  the `ImageColumn.src`) and draws them (`LegadoUI/PagedReader.swift` →
  `ReaderInlineImageView`, the bytes from `AppChapterContentProvider.chapterImages`),
  with the four image styles (撑满宽度 / 适应边框 / 文字嵌入 / 默认);
- the **image preview + the image long-press menu** — the upstream
  `ContentTextView.click` / `.longPress` open the photo dialog and the
  显示 / 刷新 / 保存 / 菜单 / 选择文件夹 popup (`LegadoUI/ReaderImageViews.swift`);
- the **automatic source change** — the upstream `ReadBookViewModel.autoChangeSource`
  looks for a working source when the book's source is gone
  (`Core/Pipeline/ChangeSource.swift` → `ChangeSourceService.autoChangeSource`
  + `ReadBook.replaceBook`);
- the **brightness that follows the system** — the upstream `ReadMenu.brightnessAuto()`
  (`LegadoUI/ReaderSystemIntegration.swift` + the toggle in
  `LegadoUI/ReaderMenuView.swift`; the whole brightness view is hidden when
  `showBrightnessView` is off, exactly like `ReadMenu.kt:124`);
- the **seek bar that adjusts the chapters** — the upstream `ReadMenu.upSeekBar`
  switches between the page slider and the chapter slider with
  `progressBarBehavior` and asks for a confirmation before the chapter jump
  (`LegadoUI/ReaderMenuView.swift`);
- the **ten functional bugs** the fresh audits found (the WebDAV credentials
  were never persisted, the welcome image was never applied, the search
  pagination was dead code, the pre-download count was hard-coded to 1, the
  discover ignored `enabledExplore`, the RSS list showed the disabled sources,
  the RSS sources could not log in, the RSS article screen had no menu, the
  RSS read records were never listed, the bookshelf management had a dead
  toggle and a no-op button) — all of them are fixed, the reports name the
  files.

### 8.7 The second wave of the audits (2026-11-04) — the open items

The four fresh audits (`Plan/audits/2026-11-04-{bookshelf-toc,settings-sources,rss-search}.md`
+ the reader audit) walked the same four areas again — this time with the port
as it is now. They reported **≈130** items that are still missing or only
partly implemented. The list below is the work list; the reports hold the
upstream file + line evidence for each one.

| The area | The open items |
|---|---|
| The reader | **mostly closed** — the read-style dialog is now reachable (`LegadoUI/ReaderSettingsView.swift` → `ReaderPreferenceRows`, embedded in the reader's 更多设置 and in the app's 阅读设置); the tip config has the `clearRepeat` rule (`Core/Reader/Config/ReaderConfig.swift` → `clearRepeatedTip(_:)`, the upstream `TipConfigDialog.clearRepeat`) and the two colour pickers (`LegadoUI/ReaderTipColorView.swift` → `ReaderTipColorField`, the upstream `TipConfigDialog`'s 提示文字颜色 / 分割线颜色); the 编辑内容 tap action opens the real editor (`Core/Pipeline/ContentEdit.swift` → `ContentEditService.loadContent/saveContent/resetContent`, the upstream `ContentEditDialog`); the in-reader search results open the whole-book search (`LegadoUI/BookToolsViews.swift` → `ContentSearchView(model:book:initialQuery:)`, the upstream `SearchContentActivity`); the day / night background image and the blurring sliders live in the THEME config (`Core/App/ThemePreferences.swift` → `dayBackgroundImagePath` / `nightBackgroundImagePath` / `dayBackgroundImageBlurring` / `nightBackgroundImageBlurring`, the upstream `PreferKey.bgImage` / `bgImageN` / `bgImageBlurring` / `bgImageNBlurring`) and the shell draws the blurred image behind the tabs (`LegadoUI/ShellBackgroundView.swift`, the upstream `BaseActivity.upBackgroundImage`); **the page turn has a real animation again** — the drag progress drives the transform, the revealed page is drawn under the current one, and the three horizontal styles differ (滑动 = both pages move, 覆盖 = the revealed page stays, 仿真 = the page folds around the hinge — `Core/Reader/PageFold.swift` → `PageFoldGeometry` (the upstream `SimulationPageDelegate.calcPoints`) + `PageTurnLayout`, `LegadoUI/PageTurnView.swift`); the reader asks whether the book should be added to the shelf when it closes (`LegadoUI/AppModel.readerDidClose` + `LegadoUI/BookDetailView.swift`, the upstream `ReadBookActivity.finish`); the bookmark editor exists in the reader and in the bookmark manager (`LegadoUI/BookmarkEditView.swift`, the upstream `BookmarkDialog`); the 朗读 action of the selection menu reads from the selection to the end of the chapter in the mode 1 — the mode is toggled by a long press on the action (`Core/App/AppSettings.swift` → `contentSelectSpeakMod`, `LegadoUI/ReaderView.swift` → `toggleReadAloudMode()`, the upstream `TextActionMenu`'s long press) — still open: the manga reader's chapter-mode progress bar, and the tip config's per-slot colours |
| The manga | **closed** — 换源 opens the change-source dialog (`LegadoUI/BookToolsViews.swift` → `ChangeSourceView`, the upstream `ChangeBookSourceDialog`); the automatic page and the automatic scroll are exclusive and run on a timer (the upstream `ScrollTimer`, every `mangaAutoPageSpeed` seconds); the horizontal scroll switches the axis of the `ScrollView`; the pinch zoom sets the scale (`MangaMode.Zoom.clamp`, the upstream `WebtoonRecyclerView.onScale`, disabled by `disableMangaScale`); the e-paper threshold has its own dialog (`LegadoUI/MangaConfigViews.swift` → `MangaEInkThresholdSheet`, the upstream `MangaEpaperDialog`) and the e-ink and the grey modes exclude each other; the automatic scroll is the upstream's pixel-wise continuous scroll (`LegadoUI/MangaView.swift` → `MangaReaderController.autoScrollTick(distance:)` + `autoScrollOffset` / `viewportHeight`, the upstream `ScrollTimer.isEnabled` → `scrollBy(distance)`) and the timers pause while the menu is visible |
| The local import | **closed** — the in-app file browser (`LegadoUI/LocalBookBrowserView.swift`, the upstream `ImportBookActivity`): the folder tree, the multi-select with 全选 / 反选 / 删除所选, 批量加入书架 (`Core/App/LocalBookImporter.swift` → `importBooks(from:)`), the sort by 名称 / 大小 / 时间 (`Core/Local/LocalBookBrowser.swift` → `Sort`, the upstream `AlphanumComparator`), 扫描文件夹 (`Core/Local/LocalBookScanner.swift`), the file-name template (`Core/Local/LocalBook.swift` → `analyzeNameAuthor(fileName:fileNameRule:scriptEngine:)`, the upstream `AppConfig.bookImportFileName` JS rule), the search filter; the zip archive import (`LocalBookImporter.importArchive(from:)` — the upstream `LocalBook.importArchiveFile`: the entries are extracted, the origin becomes `loc_book::<archive>` and the archive bit is set); a file that is already on the shelf shows the 已在书架 marker and tapping it opens the reader (`Core/Storage/LegadoStore.swift` → `hasLocalFile(fileName:)` / `localBook(fileName:)`, the upstream `BookDao.hasFile` / `getBookByFileName`; `LegadoUI/LocalBookBrowserView.swift` → `startRead(_:)`) |
| The RSS | **mostly closed** — the import has a preview dialog with the states 新增 / 更新 / 已有, the 全选 / 反选 counter and the options 保留原名称 / 保留原分组 / 保留原启用状态 / 新建分组 (`LegadoUI/RssSourceToolsViews.swift` → `RssSourceImportPreviewView`, the upstream `ImportRssSourceDialog`; the comparison and the options are in `Core/App/RssSourceImport.swift` → `items(_:local:)` / `prepare(_:local:options:)`, the upstream `ImportRssSourceViewModel`); the source debugger has a UI with the 列表页源码 / 内容页源码 (`LegadoUI/RssSourceToolsViews.swift` → `RssSourceDebugView`, the upstream `RssSourceDebugActivity`); the editor's toolbar has 保存 / 关闭 (the exit confirmation) and a 更多 menu with 调试 / 登录 / 源变量 / 清除Cookie / 自动补全 / 复制源 / 粘贴源 / 二维码分享 / 分享 / 帮助, and the rule fields are completed with the upstream's per-rule types (`LegadoUI/RssSourceManagementView.swift` → `RssSourceEditView`, the upstream `RssSourceEditActivity`); the favourite's title and group can be edited from the article reader (`LegadoUI/RssArticleReaderView.swift` → `RssFavoriteEditView`, the upstream `RssFavoritesDialog`); the per-row menu has 置顶 / 置底 / 删除 (the upstream `RssSourceAdapter`); the selection bar has 分享选中源 and 检查所选区间 (`LegadoUI/RssSourceManagementView.swift`, the upstream `res/menu/rss_source_sel.xml`); the article rows have the three layouts (the list, the compact row with the image, the two-column grid) and the read state; the import keeps the URL history (`Core/App/ImportUrlHistory.swift` → `ImportUrlHistory.Kind.rssSource` = the upstream's `rssSourceRecordKey` in the `ACache`, `LegadoUI/RssSourceManagementView.swift` → `RssSourceImportView`'s 最近导入 section) — still open: 检查选中源定时, and the adult-domain list (`app/src/main/assets/18PlusList.txt`) that the upstream refuses to import — see the deviations |
| The discover + the search | **closed** — the dynamic scope quick-switch menu (a group in the scope is removed when it is tapped, a group outside the scope replaces it — upstream `SearchActivity.onMenuOpened`), 日志 (`LegadoUI/AppLogView.swift` in a sheet), the 精准搜索 toggle re-runs the search (`SearchActivity.onCompatOptionsItemSelected`), the empty-result dialog's second branch ("切换到全部分组？"), the shelf-book suggestion chips (`SearchActivity.upHistory` + `BookDao.flowSearch`), the result row's cover / origin-count badge / latest chapter / kind list (`SearchAdapter`) and the origin collection of the merged books (`SearchModel.mergeItems` → `SearchBook.addOrigin`) — `LegadoUI/SearchView.swift` + `Core/App/SearchScope.swift` + `Core/Model/Book.swift` |
| The bookshelf + the TOC | **mostly closed** — the group filter has an entry point (the 更多 menu's 分组筛选 section with a ✓ next to the selected group, upstream `BookshelfManageActivity.upMenu`); the rows show the group names and 本地书籍 and have a 分组 button that opens the group picker and replaces the mask (upstream `BookAdapter.tvGroupS` / `tvGroup`); the batch 换源 migrates the reading progress (`Core/Pipeline/ChangeSource.swift` → `ChangeSourceService.switchSource` with the display title, the upstream `Book.migrateTo`), writes the books and the chapters and waits `batchChangeSourceDelay` seconds between two books (`Core/App/AppEnvironment.swift` → `batchChangeSource(books:source:delaySeconds:progress:)`, the upstream `BookshelfManageViewModel.changeSource`), and the delay is edited in the source picker (upstream `SourcePickerDialog.menu_change_source_delay`); the book-info menu has 上传到远程 (`Core/App/RemoteBookImport.swift` → `RemoteBookImporter.upload(book:)`, the upstream `RemoteBookWebDav.upload`), 分割长章节 (only for the local TXT books), 删除提示 (`LocalConfig.bookInfoDeleteAlert`) and 日志; the TOC's 使用替换 writes the GLOBAL `tocUiUseReplace` and 显示字数 persists the global `tocCountWords` (upstream `TocActivity.menu_use_replace` / `menu_load_word_count`); the TOC's header shows the title of the current chapter and opens the reader there; the bookmark rows show the text of the book and the note of the user (upstream `BookmarkAdapter.convert`) and the bookmark manager opens the editor (`LegadoUI/BookmarkEditView.swift`, the upstream `BookmarkDialog`); the TOC's menu has 日志; the 文件夹 shelf style is a nested navigation with the group cover (`LegadoUI/BookshelfView.swift` → `GroupFolderList` + `GroupCoverIcon`, the upstream `BookshelfFragment2` / `BooksAdapterGrid`), the group cover is picked and cleared in the group manager (`LegadoUI/BookshelfToolsViews.swift` → `GroupManageView` + `Core/App/LocalFileStore.swift` → `importFile(from:into:)`, the upstream `GroupEditDialog` — the file is copied into the app's own directory because an iOS file-picker URL is temporary); the change-source dialog has the upstream's toolbar (开始 / 停止, 书源管理, 刷新列表, 关闭 — `LegadoUI/BookToolsViews.swift` → `ChangeSourceView`, the upstream `res/menu/change_source.xml`), the group submenu (全部书源 + the groups of the enabled sources, the selected group is stored in the preference `searchGroup` — `Core/App/SearchScope.swift` → `AppSettings.searchGroup`, the upstream `AppConfig.searchGroup`), the 好评 / 差评 rating of the candidates with the scores persisted per book and per source (`Core/App/SourceConfig.swift` → `SourceConfig`, the upstream `help/config/SourceConfig.kt`) and the result row's long-press menu (置顶 / 置底 / 编辑 / 禁用 / 删除, the upstream `ChangeBookSourceAdapter.showMenu`) — still open: the 64-group limit and the batch 换源 without the per-book progress dialog |
| The settings + the sources | **mostly closed** — the about documents (贡献者 / 更新日志 / 隐私政策 / 开源许可 / 免责声明) + the crash logs + 保存日志 (`LegadoUI/AboutDocuments.swift` + `Core/Support/Markdown.swift`), the update body as Markdown, the read-record screen (the search / 删除 / the three sorts / the total time / tap-to-open / the per-row delete / the `enableReadRecord` row — `Core/App/ReadRecords.swift` + `LegadoUI/MineViews.swift`), the whole **其它设置** screen (`LegadoUI/OtherSettingsView.swift` — 主界面 / 其它设置 / 数据: 清除网页数据 / 压缩数据库 / 记录日志 / 缓存大小 / 图片保留数 / 书源编辑最大行数 / 默认书籍目录 / 自动刷新 / 加入书架时提示 / 自动清除过期缓存 / 默认替换规则 / 语言 / 线程数 / Web服务端口), the WebDAV 同步进度 gate + 自动检查新备份 + the backup toolbar (从文件恢复 / 帮助 / 日志) + the WebDAV 目录与设备名 (`LegadoUI/BackupView.swift` + `Core/App/AppWebDav.swift`; the automatic new-backup check on start: `LegadoUI/AppModel.checkNewBackup` + `LegadoUI/RootView`), the global error alert (the AppModel's `errorMessage` was set in ~40 places but never shown), the source manager's drag reorder / 检查所选区间 / 搜索该源 / the invalid-group auto-filter / the export to a real file (`LegadoUI/SourceManagerView.swift` + `Core/App/SourceManagement.swift` + `LegadoUI/DocumentExporter.swift`), the source editor's 书源类型 / coverDecodeJs / bookUrlPattern / variableComment / 搜索 / 扫码导入 / the unsaved-changes confirmation (`LegadoUI/SourceEditorView.swift`), the direct-link-upload default chooser (the three rules), and the real file exports of the replace rules / the bookmarks (JSON + Markdown) / the TXT TOC rules / the dictionary rules / the RSS sources / the shelf's used sources (`Core/App/BookmarkExport.swift` + `Core/App/DocumentExport.swift`); the welcome configuration has the `customWelcome` master switch and 删除启动图 and the cover configuration can delete the default covers and ties 显示作者 to 显示书名 (`LegadoUI/ConfigScreens.swift` → `WelcomeConfigView` / `CoverConfigView`, the upstream `WelcomeConfigFragment` / `CoverConfigFragment`); the theme editor has the `barElevation` stepper and the `fontScale` stepper with the "跟随系统" reset (`Core/App/AppSettings.swift` + `LegadoUI/ThemeEditorView.swift`, the upstream `ThemeConfigFragment`); the change-source dialog scores the books with 好评 / 差评 (persisted, `Core/App/SourceConfig.swift`, the upstream `SourceConfig`) and the result rows have the long-press menu 置顶 / 置底 / 编辑 / 禁用 / 删除 (`LegadoUI/BookToolsViews.swift`, the upstream `ChangeBookSourceAdapter.showMenu`); the imports keep the URL history — the book sources (`bookSourceRecordKey`), the replace rules (`replaceRuleRecordKey`), the RSS sources (`rssSourceRecordKey`) and the dictionary rules (`dictRuleUrls`) — with the 最近导入 list that fills the field or drops an entry (`Core/App/ImportUrlHistory.swift` + `LegadoUI/SourceManagementSupport.swift` → `ImportDocumentView` + `LegadoUI/RssSourceManagementView.swift` → `RssSourceImportView`, the upstream `ACache` + the `showImportDialog` of the four screens) — still open: the source editor's remaining help actions |

Two upstream items are deliberately **not** ported because the upstream manifest
does not register them either: the app widgets and the home-screen shortcuts.

---

## Deliberate deviations from the Android app

1. **Authentication on the local API.** The Android server has no auth and
   reflects the `Origin` header, so any web page can drive it
   (`web/HttpServer.kt:39-46`, `:134`). The iOS port requires a bearer token
   and never reflects `Origin`.
2. **Capability-based JS sandbox.** Upstream denies classes by name but leaves
   `Packages.java.*` reachable; the port exposes only the documented
   `java.*` helpers and confines file access to the app container.
3. **No widget layer** — Android Legado has none either.
4. **Cronet is dropped** — `URLSession` replaces it.
5. **No `versionCode = 10000 + git rev-list --count`** — the iOS build uses a
   monotonic counter from `Info.plist` instead.
6. **EPUB export uses a hand-written writer**, not the vendored epublib fork:
   `Local/EpubBuilder.swift` emits `mimetype`, `META-INF/container.xml`,
   `OEBPS/content.opf` and `OEBPS/toc.ncx` directly, with one embedded
   stylesheet instead of the 23 KB of APK assets. The output is EPUB 2.0 and
   structurally identical (same entry order, same navMap nesting for volume
   chapters), but it does not ship `Images/logo.png`.
7. **Export images come from a closure.** `BookExporter.imageProvider` /
   `coverProvider` are injected rather than read from an on-disk image cache,
   because the port has no downloader yet; the EPUB still rewrites every
   `<img src>` to `../Images/<md5>.<ext>` so the layout is unchanged.
8. **Backup JSON is keyed by column name**, not by the Kotlin property name
   GSON would use. The file set (15 tables + `config.xml` + the app's config
   files), the ZIP layout, the AES-ECB encryption of `servers.json` and the
   restore semantics (merge books, newest `readRecord` wins, plain-JSON
   fallback) all match upstream; only the object keys can differ where a Room
   column is renamed with `@ColumnInfo`.
9. **AES is implemented in Swift** (`Support/AES.swift`, ECB/CBC + PKCS#7)
   instead of using CryptoKit, because CryptoKit does not exist on Linux and
   the Linux build is where the port is verified. The cipher is verified
   against the FIPS-197 and NIST SP 800-38A vectors.
10. **WebDAV responses are parsed with a local-name-only scanner.** Servers
    disagree about namespace prefixes (`d:response` vs `response`), so the
    port matches on the local name; the protocol surface is the same
    (`PROPFIND`/`PUT`/`GET`/`DELETE`/`MKCOL`, Basic auth).
11. **No blocking I/O in initialisers.** Upstream's `AppWebDav` object runs
    `runBlocking { upConfig() }` on first touch (`help/AppWebDav.kt:55-59`);
    every port call is explicitly `async`.
12. **The local HTTP server is a hand-written HTTP/1.1 + RFC 6455 stack.**
    Upstream uses NanoHTTPD + NanoWSD (Java only); the port implements the
    subset it needs: request parsing with `Content-Length` bodies, keep-alive
    responses, `HEAD`/`OPTIONS`, a bearer token, and one allowed CORS origin
    (`Sources/LegadoServer/`). The endpoint set is a subset of upstream's 22
    routes — the bookshelf, chapter list, book content, book sources and
    replace rules reads plus the book/source/progress writes.
13. **The WebSocket port is protocol-complete but endpoint-light.** The
    handshake, the frame codec and the ping/pong handling match RFC 6455 (the
    accept token is verified against the RFC example), but upstream's three
    endpoints (`bookSourceDebug`, `rssSourceDebug`, `searchBook`) are not
    implemented yet; the server takes a pluggable `webSocketHandler`.
14. **The UI layer is compiled on Linux through a SwiftUI shim.** SwiftUI
    exists only on Apple platforms and the port is verified on Linux, so
    `Sources/LegadoUI` imports the real SwiftUI on Apple and the hand-written
    `Sources/LegadoUIShim` (view builder, state, modifiers, scene) everywhere
    else. The same view sources are therefore type-checked by the Linux build
    and by the Linux CI job; the shim never renders.
15. **The bookshelf sorts names with the ICU Chinese collation.** Upstream
    compares with `cnCompare` — a `Collator` for `ULocale.SIMPLIFIED_CHINESE`
    (`StringExtensions.kt:97-103`). The port compares with
    `String.compare(_:locale:)` and the `zh_Hans_CN` locale
    (`Core/App/Bookshelf.swift`), which is the same ICU collation; the
    difference is that the upstream's `Collator` has no comparison options
    (the tertiary strength, no decomposition), so the port passes none
    either.
16. **The read-aloud unit is the paragraph, like upstream.** Upstream does not
    split sentences: the chapter content is split on `\n`, the empty lines and
    the lines that consist only of punctuation/symbols are dropped, and each
    remaining paragraph is one spoken unit. The port reproduces that in
    `Reader/ReadAloud.swift` (`ReadAloudSplitter`), including the upstream
    `notReadAloudRegex`.
17. **The iOS bundle is generated from `project.yml`.** XcodeGen builds
    `LegadoApp.xcodeproj` from a YAML spec (the SwiftPM package stays the
    single source of the code); the project registers the `legado://` URL
    scheme, enables the Files-app sharing (`UIFileSharingEnabled`,
    `LSSupportsOpeningDocumentsInPlace`) and relaxes ATS for the plain-HTTP
    book sources. The project itself can only be compiled on a Mac, so the
    Linux CI verifies the package and the macOS CI job builds the app.
18. **A headless smoke test replaces the UI on Linux.** `Sources/LegadoApp`
    builds an executable that runs `LegadoSmokeTest` instead of a UI loop
    (schema → groups → source import → bookshelf → search → reader
    pagination → the local HTTP API), so the whole stack can be exercised
    without a display server.
19. **The Chinese conversion ships the OpenCC tables.** Upstream wraps the
    `quick-transfer` library, whose dictionaries are OpenCC derived; the port
    generates the same tables from the OpenCC data files
    (`Scripts/fetch_opencc.sh` + `Scripts/gen_chinese_table.py` →
    `Reader/ChineseCharacters.swift`, 7,102 one-to-one character mappings, and
    `Reader/ChinesePhrases.swift`, 38,972 phrase mappings). The upstream
    `ChineseUtils.fixT2sDict` exclude list is reproduced verbatim, so the words
    whose traditional form is a different valid word (華樂, 載入, 菲林, …) are
    kept as they are.
20. **The source verification follows the upstream check service, not the
    CAPTCHA helper.** `help/source/SourceVerificationHelp.kt` in the upstream
    solves a CAPTCHA; the actual 校验 lives in `service/CheckSourceService.kt`.
    The port implements the latter: the search URL, the explore URL, the
    detail page, the table of contents (the first two chapters) and the
    content, the Chinese invalid-group names on the source and the
    `// Error: …` comment. An empty search or explore rule is only a marker —
    upstream's `getInvalidGroupNames()` ignores the groups that do not contain
    "失效", so the check still reports 校验成功.
21. **The explore categories are parsed from `exploreUrl`.** Upstream
    `BookSource.exploreKinds()` reads the `exploreUrl` field — either a JSON
    array of `ExploreKind` objects or a list of `分类::网址` pairs separated by
    `&&` or newlines (`help/source/BookSourceExtensions.kt:41-89`). The port
    reproduces that in `Pipeline/ExploreKinds.swift`; the `ruleExplore` field
    holds the rule of the category list, not the list itself.
22. **The content search searches the processed text.** Upstream feeds the
    chapter through `ContentProcessor.getContent(…, includeTitle = true)` and
    then looks for the query as a plain, case-sensitive substring; the query
    itself is never converted, which is why the upstream empty state reads
    `搜索内容为空，请检查净化或简繁设置`. The port reproduces that, including
    the ±20 characters of context and the non-overlapping matches.
23. **The login information is stored unencrypted.** Upstream encrypts
    `userInfo_<key>` with AES and the device id as the key
    (`BaseSource.putLoginInfo`); iOS has no android id, so the port keeps the
    plain JSON in the cache table (the same table the upstream uses).
24. **The cookies are persisted in the user defaults.** Upstream keeps them in
    the SharedPreferences (`CookieStore.kt:25-71`); the port's
    `UserDefaultsCookiePersistence` does the same, and the web view login
    copies the cookies in and out of the WKWebView cookie store explicitly
    (the Android CookieManager is global, the iOS one is not).
25. **The rule scripts run with an explicit capability allow-list.** Upstream
    guards the Rhino engine with a class deny-list
    (`RhinoClassShutter.kt`), so everything that is not on the list — the whole
    `Packages.java.*` tree included — stays reachable. The port grants the
    capabilities one by one (`ScriptCapabilities`: the network, the file
    read/write inside the sandbox, the cookies, the cache, the source data);
    a binding the script was not granted is not even exposed to it.
26. **The source editor edits the raw rule JSON.** Upstream edits every rule
    with a structured form (`ui/book/source/edit/`); the port edits the rule
    JSON, because that is exactly how the rules are stored
    (`BookSource.ruleSearch` and friends are JSON strings) and because it
    keeps every rule field the upstream form hides.
27. **The local API answers with the upstream `ReturnData` envelope.** The
    Android server has no authentication and no envelope — every route returns
    the raw payload. The port keeps the upstream payload *shape* (so the
    upstream web client works unchanged) but wraps it in
    `{isSuccess, errorMsg, data}` and keeps the business errors in `errorMsg`
    with the HTTP status 200, exactly like upstream `api/ReturnData.kt`.
28. **The web client is authenticated.** Upstream's server accepts every
    request from every origin; the port requires a bearer token. The upstream
    Vue bundle is served with a small inline script that adds the
    `Authorization` header and the `token` query parameter, so the browser
    experience is unchanged while the API stays closed.
29. **The volume keys do not turn the pages.** Upstream installs a
    `BroadcastReceiver` for the volume keys (`BaseReadBookActivity.kt:377-391`)
    and a `UIApplication` subclass to receive them; a SwiftUI app can do
    neither, so the reader is driven by the taps, the swipes and the media
    buttons (`LegadoUI/MediaCommandBridge.swift`).
30. **The hardware page-turn keys are not configurable.** Upstream's
    `PageKeyDialog` stores the Android key codes in `prevKeyCodes` /
    `nextKeyCodes`; iOS has no hardware key codes to pick, so the preference
    keys exist but no dialog does (`Core/App/AppSettings.swift`).
31. **The system TTS settings are not opened.** Upstream sends the
    `ACTION_TTS_SETTINGS` intent (`ReadAloudConfigDialog.kt:107`); iOS has no
    such screen, so the read-aloud engine is configured inside the app
    (`LegadoUI/ReaderAloudDialogView.swift`).
32. **The media button does not wake the app.** Upstream's
    `mediaButtonOnExit` makes the media key bring the app back
    (`MediaButtonReceiver.kt:103`); the port keeps the preference but the
    behaviour is meaningless on iOS, where the app is foreground-only.
33. **The adult-domain list is not carried.** Upstream refuses to import the
    RSS sources whose host is on `app/src/main/assets/18PlusList.txt` (the
    hosts are base64-encoded, `help/source/SourceHelp.kt:119-129`); the port
    imports every source the user gives it. The list is a content policy
    artefact of the upstream distribution, not a feature.

## Known upstream quirks that are reproduced on purpose

* `@CSS:` keeps its prefix in the rule text; the CSS matcher strips it.
* The `:` regex marker only applies in the "all in one" mode used by
  `getElement` / `getElements`.
* `##` replacement: the trailing whitespace of a replacement is trimmed
  because the literal chunk is trimmed before the split.
* `replaceFirst` applies the replacement to the *matched* text only and drops
  the rest of the string.
* `splitRule("&&", "||", "%%")` splits on the separator found **first** only.
* An empty `{{js}}` result keeps the previous step's value.
