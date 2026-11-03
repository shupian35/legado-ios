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
| Reader configuration (5 style slots) | `help/config/ReadBookConfig.kt` (756) | `Reader/Config/ReaderConfig.swift` | [x] |
| Reader state machine (load/progress/preload) | `model/ReadBook.kt` (1054) | `Reader/ReadBook.swift` | [x] (the new-chapter check `upToc` included, 13 tests) |
| Nine-zone tap mapping | `AppConfig.clickAction*`, `ReadView.kt:130-140` | `Reader/ReaderInteraction.swift` (`TapZoneMapper`, `ClickAction`, `ReaderClickConfiguration`) | [x] (13 tests) |
| Text selection, copy, share | `ContentTextView.kt` | `Reader/Selection.swift` (the selection model, the word/paragraph snapping) + `LegadoUI/SelectionOverlay.swift` (the overlay with 复制 / 取消) | [x] (the model + the overlay) |
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
| RSS subscribe / read | `model/rss/*`, `ui/rss/*` | `Pipeline/Rss.swift` (rule + default parser, next page, article content) | [x] |
| RSS stars / read records / groups | `ui/rss/*`, `data/entities/RssStar.kt` | `Core/App/RssLibrary.swift` (the groups, the favourites, the read records) + `Model/Misc.swift` (RssStar/RssReadRecord) + `LegadoUI/RSSView.swift` (the group filter, the favourite toggle, the favourites list) | [x] (9 tests) |
| Downloads + cache book | `service/{DownloadService,CacheBookService}.kt`, `model/CacheBook.kt` | `Net/BookCache.swift` (chapter cache + image cache + queue/retry) | [x] |
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
| Bookshelf (list + grid styles) | `ui/main/bookshelf/*` | `LegadoUI/BookshelfView.swift` + `LegadoUI/BookshelfManageView.swift` (the batch management) + `Core/App/Bookshelf.swift` (the group filter, the six sorts, the search) | [x] (the list style and the grid style — upstream `bookshelfLayout` 0 = the list, otherwise a grid with `bookshelfLayout + 2` columns; the batch management — the multi-select, the batch update / delete / group move — is ported) |
| Book info / TOC / source switch | `ui/book/{info,toc,source,changeSource}/*` | `LegadoUI/BookDetailView.swift` + `LegadoUI/TocView.swift` + `LegadoUI/BookshelfManageView.swift` (`BookInfoMenuView`) + `LegadoUI/BookToolsViews.swift` (`ChangeSourceView`) | [x] (the change source searches the enabled sources and remaps the reading progress; the book-info menu — the metadata editor, the share, the pin, the cover, the group, the variables, the delete — and the TOC screen — the TOC regex, the long-chapter split, the reverse, the word count, the Markdown export, the bookmark tab — are ported, see §8 rows 11 and 12) |
| Reader (page rendering + the state machine) | `ui/book/read/*` | `LegadoUI/ReaderView.swift` + `LegadoUI/ReaderMenuView.swift` (the menu: the page seek, the chapter list, the read style, the read aloud, the brightness) + `LegadoUI/PagedReader.swift` + `LegadoUI/PageTurnView.swift` + `Reader/ReadBook.swift` | [x] (the state machine, the page model and the menu are ported; the page is drawn like the upstream canvas — every laid-out line at its own `lineTop` / `startX`, the page size follows the screen and the layout is computed again when it changes (`ReaderController.updatePageSize`); the nine-zone tap area, the horizontal page-turn drag, the five page-turn styles and the system integrations — the keep-screen-on, the brightness, the orientation, the lock-screen/headset buttons — are applied; the volume keys stay a deviation, see §8) |
| Search / content search | `ui/book/{search,searchContent}/*` | `LegadoUI/DiscoverView.swift` (`SearchView`) + `LegadoUI/BookToolsViews.swift` (`ContentSearchView`) | [x] (the content search reads the downloaded chapters) |
| Settings (all `PreferKey`s) | `ui/config/*`, `help/config/*` | `LegadoUI/SettingsView.swift` + `LegadoUI/AdvancedSettingsView.swift` (every key editable) + `LegadoUI/MineViews.swift` (the TXT TOC rules, the dictionary rules, the read records, the HTTP TTS, the file management, the about) + `Core/App/AppSettings.swift` (the 182 upstream keys) | [x] (the curated screen plus the advanced screen that edits every `SettingsKey` with its raw value; the port represents **exactly** the 182 upstream `PreferKey` constants — `Tests/LegadoCoreTests/SettingsKeyParityTests.swift` fails if one is missing or if the port invents one) |
| Theme (day / night / E-Ink) | `help/config/ThemeConfig.kt` | `Core/App/Theme.swift` (`AppTheme`, `ThemeMode`, `ThemeManager`, the four upstream themes) + `LegadoUI/ThemeSupport.swift` | [x] (the manager, the settings picker and the background colour are wired) |
| Import / export / backup UI | `ui/import`, `ui/export`, `ui/file` | `LegadoUI/SourceManagerView.swift` (the source import/export) + `LegadoUI/BackupView.swift` (the local ZIP backup, the restore, the WebDAV upload/download) | [x] (the backup screen writes the upstream ZIP into `<documents>/backup` and restores it, and it drives the WebDAV client) |
| Notifications | `App.kt:179-219`, `AppConst.kt:19-21` | `Core/App/Notifications.swift` (the three channels, the content factories, the six media actions) + `LegadoUI/Notifications.swift` (`NotificationService`, UserNotifications) + `LegadoUI/ReadAloudPlatform.swift` (the transport notification) | [x] (the three channels exist, the download / read-aloud notifications are posted and the transport notification carries the six upstream actions — 上一章 / 上一段 / 暂停 / 下一段 / 下一章 / 停止) |
| iOS bundle (Xcode project, Info.plist, URL scheme, file sharing) | `app/src/main/AndroidManifest.xml` | `project.yml` (XcodeGen) → `LegadoApp.xcodeproj`, `Sources/LegadoAppUI/Info.plist` | [x] (the project is generated; it can only be built on a Mac; the Info.plist carries the camera usage description (the QR scanner would be killed without it), the `audio` background mode (the read-aloud with the screen off), the deep-link scheme, the document types and the seven launcher icons, which `Scripts/render_launcher_icons.py` renders from the upstream vector drawables) |
| The Apple-only code paths are type-checked on Linux | — (the port's own safety net) | `Scripts/apple-stubs/` (the UIKit / AVFoundation / WebKit / MediaPlayer / CoreImage / CoreText / PDFKit / UserNotifications stubs) + `Scripts/typecheck_apple.sh` + the CI step | [x] (the `#if canImport(UIKit)` blocks are never compiled by the Linux build — the stub modules make `canImport` true, so the same sources are type-checked with the Apple branches enabled; the check has already caught 13 real iOS build errors) |
| Book source editor | `ui/book/source/edit/*` | `LegadoUI/SourceEditorView.swift` (the fields, the rules as raw JSON, the check, the login, the rule help) | [x] (the upstream edits the rules with a structured form; the port edits the rule JSON, which is how the rules are stored) |
| Replace rules / bookmarks / group management | `ui/book/replace/*`, `ui/book/manage/*`, `ui/main/bookshelf/groups/*` | `LegadoUI/ManageViews.swift` (`ReplaceRuleView` + `ReplaceRuleEditor`, `BookmarkView`, `BookGroupView`) | [x] (the rule editor has a live test field, the groups use the first free power of two) |

---

## 8. The known gaps (the independent audit of 2026-11-03)

A read-only audit walked the whole upstream `app/src/main/java/io/legado/app/`
tree (the `ui/` folder, the services, the receivers, the preferences XML and
the manifest) and compared every user-visible feature with the port. The
matrix above claims `[x]` only where the port really offers the feature; the
gaps below are the honest remainder. They are ordered by how visible they are
to a user.

| # | The upstream feature | Upstream | The state in the port |
|---|---|---|---|
| 1 | **The reader menu** (the page seek, the chapter list, the read style, the read aloud, the brightness, the night-mode toggle, the source actions, the replace-rule popup) | `ui/book/read/ReadMenu.kt` (590) + `ui/book/read/config/*` | **done** — `LegadoUI/ReaderMenuView.swift` |
| 2 | **The read-aloud transport notification** with the six media actions, the lock-screen controls and the headset buttons | `service/BaseReadAloudService.kt:594-670`, `receiver/MediaButtonReceiver.kt` | **done** — the notification is posted with the six upstream actions (`Core/App/Notifications.swift` + `LegadoUI/Notifications.swift`) and the headset buttons / the lock-screen controls are wired through the `MPRemoteCommandCenter` (`LegadoUI/MediaCommandBridge.swift`, Apple-only) |
| 3 | **The reader system integrations** — the keep-screen-on, the volume keys, the screen orientation, the brightness, the hidden status bar | `ui/book/read/BaseReadBookActivity.kt:148/161/239`, `ReadBookActivity.kt:699` | **mostly done** — `LegadoUI/ReaderSystemIntegration.swift` applies the keep-screen-on, the brightness and the orientation, and `LegadoUI/StatusBarHost.swift` hides the status bar; the volume keys are a **deliberate deviation** (intercepting them needs a `UIApplication` subclass, which SwiftUI cannot install — the preference is kept and exposed) |
| 4 | **The 我的 tab entries** — the TXT TOC rules, the dictionary rules, the read records, the file management, the about screen, the help | `ui/book/toc/rule/TxtTocRuleActivity.kt`, `ui/dict/rule/DictRuleActivity.kt`, `ui/about/ReadRecordActivity.kt`, `ui/file/FileManageActivity.kt`, `ui/about/AboutActivity.kt` | **done** — `LegadoUI/MineViews.swift` (the TXT TOC rules, the dictionary rules, the read records, the file management, the about, the HTTP TTS) |
| 5 | **The 订阅 tab management** — the RSS source editor, the subscription rules, the article sorting, the article read records, the favourites editor, the article WebView | `ui/rss/**` | **done** — the RSS source editor + the source groups are there (`LegadoUI/ManageSources.swift`), the articles are read, grouped and starred (`Core/App/RssLibrary.swift`), the per-source sort tabs are parsed exactly like the upstream (`Core/App/RssSortUrls.swift` + `LegadoUI/RSSView.swift`), the subscription rules (the remote import of the sources / the RSS sources / the replace rules) are `Core/App/RemoteImport.swift` + `LegadoUI/RuleSubView.swift`, and the article is shown in the read mode with the original page in the in-app browser (`LegadoUI/RSSView.swift` + `LegadoUI/BrowserAndCacheViews.swift`) |
| 6 | **The book-source management extras** — the source groups, the sorting, the bulk enable / delete, the source debug screen | `ui/book/source/manage/GroupManageDialog.kt`, `BookSourceSort.kt`, `ui/book/source/debug/*` | **done** — the source groups and the sorting are there (`LegadoUI/ManageSources.swift`), the bulk enable / disable / delete are in `LegadoUI/AppModel.swift` and the debug screen is `LegadoUI/SourceDebugView.swift` |
| 7 | **The QR scanner** (the upstream feature is a scanner, the port only generates) | `ui/qrcode/QrCodeActivity.kt` | **done** — the generation is done (`CIQRCodeGenerator`) and the capture is `LegadoUI/QRScannerView.swift` (`AVCaptureSession` + `AVCaptureMetadataOutput`, Apple-only; the Linux build falls back to a text field) |
| 8 | **The in-app browser** (the chapter URL, the RSS article, the source debug open it) | `ui/browser/WebViewActivity.kt` | **done** — `LegadoUI/BrowserAndCacheViews.swift` (`InAppBrowserView` with a `WKWebView`) |
| 9 | **The bookshelf batch management** (the multi-select, the batch update / delete / group / source switch / cache clear) | `ui/book/manage/BookshelfManageActivity.kt` (377) | **done** — `LegadoUI/BookshelfManageView.swift` (the multi-select, the batch delete / update / move) |
| 10 | **The cache management screen** (the cached chapters, the clear, the bulk export) | `ui/book/cache/CacheActivity.kt` (540) | **done** — `LegadoUI/BrowserAndCacheViews.swift` (`CacheManageView`: the cached books, their size, the clear) |
| 11 | **The book-info menu** (the metadata editor, the share, the pin, the variables, the copy of the URL, the cover, the group, the delete) | `ui/book/info/BookInfoActivity.kt` (725) | **done** — `LegadoUI/BookshelfManageView.swift` (`BookInfoMenuView`: the metadata editor, the share, the pin, the copy of the URL, the variables, the cover, the delete) |
| 12 | **The TOC screen features** (the TOC regex, the split of the long chapters, the reverse, the word count, the Markdown export, the bookmark tab) | `ui/book/toc/TocActivity.kt` (193) | **done** — `LegadoUI/TocView.swift` (the chapter list, the search, the 书签 tab, the 反转目录 / 使用替换 / the Markdown export, the 目录正则, the 分割长章节 and the 显示字数) + `Core/Pipeline/TocOperations.swift` (the reverse, the bookmark JSON/Markdown, the TOC re-parse, the long-chapter flag) |
| 13 | **The local book import extras** (the folder scan, the remote books over WebDAV / the local server, the MOBI / AZW formats) | `ui/book/import/local/ImportBookActivity.kt`, `ui/book/import/remote/RemoteBookActivity.kt` | **done** — the file import works (TXT / EPUB / UMD / PDF / MOBI / AZW), the folder scan is `Core/Local/LocalBookScanner.swift`, the remote import over WebDAV is `Core/App/RemoteBookImport.swift` + `LegadoUI/RemoteBookView.swift` (the listing, the sorting with the upstream `AlphanumComparator`, the download and the import), and the MOBI / AZW parser is a port of the upstream `lib/mobi/` (`Core/Local/Mobi/MobiLibrary.swift` + `Core/Local/Mobi/MobiLocalBook.swift`: the PalmDB container, the PalmDOC / MOBI / EXTH / KF8 headers, the plain / LZ77 / HUFF-CDic decompressors, the NCX table of contents, the KF6 page-break sections and the KF8 skeletons and fragments) |
| 14 | **The inbound share target and the document types** ("Open with" for txt / json / epub / pdf / mobi / azw, the `ACTION_SEND` text share, the "process text" action) | `ui/association/FileAssociationActivity.kt`, `receiver/SharedReceiverActivity.kt`, `AndroidManifest.xml` | **done** — `Core/App/FileAssociation.swift` (the classification), `LegadoUI/DeepLinkHandler.swift` (`handleFile` — the JSON / the local book / the report) + the `CFBundleDocumentTypes` in `project.yml` |
| 15 | **The first-run welcome screen, the alternate app icons, the local password, the update check** | `ui/welcome/WelcomeActivity.kt`, `help/LauncherIconHelp.kt`, `ui/association/VerificationCodeActivity.kt`, `help/AppUpdate.kt` | **done** — the update check (`Core/App/AppUpdate.swift` + the 检查更新 button in `LegadoUI/MineViews.swift`), the first-run splash (`LegadoUI/WelcomeView.swift` + the `defaultToRead` in `LegadoUI/AppModel.swift`), the source verification / the captcha (`Core/Script/SourceVerification.swift` + `LegadoUI/VerificationView.swift`), the alternate app icons (`Core/App/LauncherIcon.swift` + `LegadoUI/LauncherIconView.swift`; the icons are rendered from the upstream vector drawables by `Scripts/render_launcher_icons.py`) and the local password (`Core/App/LocalConfig.swift` + `LegadoUI/LocalPasswordView.swift` — it is the key of the encrypted backup entries, as in the upstream `help/storage/BackupAES.kt`) |
| 16 | **The theme editor** (the four day + four night colour keys, the background image, the theme import/export) | `res/xml/pref_config_theme.xml` | **done** — `LegadoUI/ThemeEditorView.swift` (the name, the night toggle, the four colour keys, the save / export / import) + `Core/App/Theme.swift` (`update(index:theme:)`, `exportJSON`, `importJSON`) |
| 17 | **The reader as a paged view** (the upstream draws the pages on a canvas) | `ui/book/read/page/*` | **done** — the page model, the pagination, the page-turn animations (`Core/Reader/PageTurn.swift`), the nine-zone tap mapping (`Core/Reader/ReaderInteraction.swift` + `LegadoUI/PagedReader.swift`), the canvas-like drawing of the laid-out lines (`LegadoUI/PagedReader.swift` places every line at its own `lineTop` / `startX` like the upstream `TextPage.drawPage`), the page size that follows the screen (`ReaderController.updatePageSize` + `ReadBook.reloadCurrentChapter` — the layout is computed again when the device is rotated) and the horizontal page-turn drag (`LegadoUI/PageTurnView.swift`) are ported; the text metrics are the real ones on iOS (`Core/Reader/Layout/CoreTextMeasurer.swift` — `NSAttributedString` + `UIFont`, the letter spacing in ems like the upstream `Paint.letterSpacing`); the fallback for the platforms without CoreText is the approximation measurer |

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
15. **The bookshelf sorts names without pinyin.** Upstream compares with
    `cnCompare` (a pinyin-aware collation); the port uses a
    case/diacritic/width-insensitive comparison with a code-point tie breaker
    (`Core/App/Bookshelf.swift`), so a Chinese title sorts by Unicode order
    instead of by pinyin.
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
