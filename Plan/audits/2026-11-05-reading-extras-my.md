# Missing-feature audit — the reading extras + the 我的 pages (2026-11-05)

Paths: `U:` = `D:\code\vscode\legado\app\src\main\java\io\legado\app\`
`P:` = `D:\code\vscode\legado-ios\Sources\`
`RES:` = `D:\code\vscode\legado\app\src\main\res\`

29 items that are genuinely missing or only partly implemented (16 fully missing, 13 partial)
out of roughly 130 upstream user-visible features enumerated in this area ⇒ ≈78 % of the area is ported.

| the upstream feature | the upstream evidence | the port's closest code | the state |
|---|---|---|---|
| Read-aloud panel: jump to the previous/next chapter while reading aloud | `U:ui/book/read/config/ReadAloudDialog.kt:104-105` (tvPre→`ReadBook.moveToPrevChapter`, tvNext→`moveToNextChapter`); `RES:layout/dialog_read_aloud.xml:21-35,99-113` | `P:LegadoUI/ReaderView.swift:2200-2229` (readAloudBar = 上一段/暂停-继续/下一段/停止 only) | Missing |
| Read-aloud panel: live auto-stop timer slider + the remaining-minutes readout | `U:ui/book/read/config/ReadAloudDialog.kt:134-140` (0/5/10/15/30/60/90/180), `:155-163` (seekTimer→`ReadAloud.setTimer`), `:190-198` (`upTimerText`) | `P:LegadoUI/ReaderAloudDialogView.swift:108-120` — a static Picker in the settings sheet; the bar shows no timer | Partial |
| Read-aloud panel: 目录 / 主菜单 / 设置 / 到后台 shortcut row | `RES:layout/dialog_read_aloud.xml:247-281,288-323,330-364,371-405`; `U:ui/book/read/config/ReadAloudDialog.kt:97,101,113,114` | `P:LegadoUI/ReaderMenuView.swift:700-702` (朗读设置 → `ReaderAloudDialogView`); 目录 exists in the reader menu; no in-panel shortcuts | Partial (到后台 is Android-only) |
| Per-book TTS engine override (朗读引擎 per book) | `U:model/ReadAloud.kt` (`ReadBook.book?.getTtsEngine() ?: AppConfig.ttsEngine`); `U:ui/book/read/config/SpeakEngineDialog.kt:143,151` (`setTtsEngine`) | `P:LegadoCore/App/AppSettings.swift:838-841,898-903` (global only); `P:LegadoUI/ReaderAloudDialogView.swift:170-177` writes the global `ttsEngineId`; `P:LegadoCore/Model/BookReadConfig.swift:28 ttsEngine` is never read/written by any UI | Missing |
| HTTP TTS engine list: import local / import online / export / delete | `U:ui/book/read/config/SpeakEngineDialog.kt:181-189`, `:277-279` (`ivMenuDelete`→`httpTTSDao.delete`) | `P:LegadoUI/MineViews.swift:478-490` — 添加 + 恢复默认 only (the JSON support exists in `P:LegadoCore/App/DeepLink.swift` `ImportKind.httpTts` but no UI reaches it) | Missing |
| HTTP TTS editor: `concurrentRate`, `loginUi`, `loginCheckJs` (+jsLib/enabledCookieJar), copy/paste source, log, help | `U:ui/book/read/config/HttpTtsEditDialog.kt:82,84,85,113,116,119,120` | `P:LegadoUI/MineViews.swift:528-554` — 名称/地址/内容类型/请求头/登录地址 only (the Core model has the fields: `P:LegadoCore/Model/Misc.swift:220-226`) | Missing |
| HTTP TTS engine login (SourceLoginActivity, type=httpTts) | `U:ui/book/read/config/SpeakEngineDialog.kt:263-266` | `P:LegadoUI/MineViews.swift:536` — only a 登录地址 text field; no login action | Missing |
| Dictionary popup: one tab per enabled dictionary rule | `U:ui/dict/DictDialog.kt` + `U:ui/dict/DictViewModel.kt` (a tab per enabled `DictRule`) | `P:LegadoUI/DictDialogView.swift` (single result) and `P:LegadoUI/ReaderView.swift:1462` (`DictSearcher.search` over all rules, first hit wins) | Partial |
| Dict rules: QR-code import | `U:ui/dict/rule/DictRuleActivity.kt:135`; `RES:menu/dict_rule.xml` | `P:LegadoUI/MineViews.swift:209-212,235-237` — import local + import online only | Missing |
| Dict rules: delete, bulk enable/disable, drag reorder, inline enable toggle | `U:ui/dict/rule/DictRuleActivity.kt:144,148,152,104-105` | `P:LegadoUI/MineViews.swift:169-264`, the editor `:267-295` — no delete, no selection mode, no reorder | Missing |
| Dict rules: help document (dictRuleHelp.md) + copy/paste rule | `U:ui/dict/rule/DictRuleActivity.kt:137`; `RES:assets/web/help/md/dictRuleHelp.md`; `U:ui/dict/rule/DictRuleEditDialog.kt` (copy_rule/paste_rule) | `P:LegadoUI/MineViews.swift:169-295` — no help entry, no copy/paste | Missing |
| Book metadata edit: 书籍类型 (文本/图片/音频) + 刷新封面 | `U:ui/book/info/edit/BookInfoEditActivity.kt:99-112` (spType), `:93-96` (tvRefreshCover), `:81-87` (ChangeCoverDialog), `:88-92` (pick image) | `P:LegadoUI/BookshelfManageView.swift:798-826` — 书名/作者/分类/封面/简介 only (更换封面 is a separate menu entry `:688-690`) | Partial |
| webFile book download / import + the archive (zip) import from the book page | `U:ui/book/info/BookInfoActivity.kt:437-462` (showWebFileDownloadAlert), `:626-690` (importOrDownloadWebFile / importArchiveBook) | `P:LegadoCore/Pipeline/BookInfoAssembler.swift:105-118` (the metadata only) — no UI/Core path downloads or imports a webFile book | Missing |
| Local book: re-download / merge the WebDAV remote copy on refresh | `U:ui/book/info/BookInfoViewModel.kt:141-148` (`getRemoteBook`/`downloadRemoteBook`), `:500-507` (`changeToLocalBook`→`LocalBook.mergeBook`) | `P:LegadoUI/BookDetailView.swift:527-543` — the refresh only reloads a *web* book through its source | Missing |
| "删除原文件" must really delete the local file | `U:ui/book/info/BookInfoActivity.kt:589-602`; `U:model/localBook/LocalBook.kt:377-392` (`if (deleteOriginal) FileUtils.delete(book.bookUrl)`) | `P:LegadoUI/BookshelfManageView.swift:409-421` (the flag is written, the file is kept); `P:LegadoCore/App/AppEnvironment.swift:337-340 deleteBook` has no deleteOriginal; `LocalFileStore.removeFile` is only used for the cover/welcome images | Partial (no-op) |
| The 删除提示 toggle must guard the delete on the book page | `U:ui/book/info/BookInfoActivity.kt:583-616` (confirm + the checkbox when `LocalConfig.bookInfoDeleteAlert`) | `P:LegadoUI/BookDetailView.swift:123-125 → 547-556 → P:LegadoUI/AppModel.swift:1077-1084` — the delete happens immediately; the toggle at `BookDetailView.swift:188-193` is never consulted | Missing |
| 分享 from 书籍信息 shares `bookUrl#bookJson` (+QR) | `U:ui/book/info/BookInfoActivity.kt:214-220` (`shareStr = "${it.bookUrl}#$bookJson"`) | `P:LegadoUI/BookshelfManageView.swift:715-717` shares only the URL (the correct payload exists at `P:LegadoUI/BookDetailView.swift:466-469,486-491`) | Partial (minor) |
| 我的 → TXT目录规则: import local/online/QR, delete, bulk enable/disable, drag reorder, help | `U:ui/book/toc/rule/TxtTocRuleActivity.kt:135` (QR), `:137` (help), `:243,247` (enable/disable), `:251` (export), `:98-101` (reorder), `:143-151` (delete) | `P:LegadoUI/MineViews.swift:29-123` — 添加/恢复默认/导出 only; the same rule set is fully managed in the TOC screen's picker `P:LegadoUI/TocRegexPickerView.swift:103-120` + `:85,149`; the drag reorder is missing everywhere (`sortNumber` exists at `P:LegadoCore/Model/Misc.swift:428` but no UI writes it) | Partial |
| 阅读排版: 共享排版 (shareLayout → a separate shareReadConfig.json) | `U:ui/book/read/config/ReadStyleDialog.kt:104,142-143`; `U:help/config/ReadBookConfig.kt:222-226,243,422` | `P:LegadoCore/App/AppSettings.swift:84` (`SettingsKey.shareLayout`) + `P:LegadoCore/App/BackupIgnoreConfig.swift:85` — no UI toggle | Missing |
| Font picker: choose a font folder and browse all its .ttf/.otf | `U:ui/font/FontSelectDialog.kt:47` (the regex `(?i).*\.[ot]tf`), `:107-118` (系统字体), `:119-121` (打开文件夹) | `P:LegadoUI/SettingsView.swift:161-166,295-308` (a single file via fileImporter → `P:LegadoUI/FontLoader.swift:24-40`); `P:LegadoUI/ReaderSettingsView.swift:400-435` (a path field) | Partial |
| Crash log: clear the crash logs | `U:ui/about/CrashLogsDialog.kt:64` (`menu_clear`→`viewModel.clearCrashLog()`) | `P:LegadoUI/AboutDocuments.swift:239-275` — a list only, no clear | Missing (minor) |
| 保存日志 packages the logs+the crash into a zip ("logs.zip") | `U:ui/about/AboutFragment.kt:124-141,167-187` (`copyLogs` → logs.zip in the backup dir) | `P:LegadoUI/AboutDocuments.swift:280-305` (`LogExporter.export` → a plain "logs.txt") | Partial (logcat is Android-only) |
| About page: 分享 app / 评分 | `U:ui/about/AboutActivity.kt:53` (menu_scoring → the Play Store), `:54-56` (menu_share_it) | `P:LegadoUI/MineViews.swift:630-769` (AboutView) — no share/rate entry | Missing (minor) |
| App-level 使用帮助 document (appHelp.md) | `U:ui/main/my/MyFragment.kt:70` (`menu_help` → showHelp "appHelp"); `RES:assets/web/help/md/appHelp.md` | `P:LegadoUI/MineViews.swift:673-675` → `P:LegadoUI/SourceEditorView.swift:474-493` (ruleHelp only); the 阅读界面帮助 exists at `P:LegadoUI/AppLogView.swift:80-98` | Missing (minor) |
| 我的: show / copy / open the Web-service address | `U:ui/main/my/MyFragment.kt:83-104` (the pref summary = `WebService.hostAddress`; the long press → 复制地址 / 浏览器打开) | `P:LegadoUI/SettingsView.swift:187-191` — the toggle + the port only; `P:LegadoServer/LegadoServer.swift:455-486,234` computes the addresses but no UI shows/copies them | Missing |
| 文件管理: a generic app-file browser (breadcrumb, search, open, delete) | `U:ui/file/FileManageActivity.kt:70-96` (search), `:120-131` (breadcrumb), `:158-228` (list/open/delete) | `P:LegadoUI/MineViews.swift:562-625` — 书籍缓存/清空缓存/缓存管理/本地书籍/备份 only | Partial |
| 远程书籍 (WebDAV): server config, search, 全选/反选, help, log, tap-to-read | `U:ui/book/import/remote/RemoteBookActivity.kt:117` (ServersDialog), `:144-150`, `:206-208` (search), `:89,119` (webDavBookHelp), `:118` (AppLogDialog), `:227-245` (tap→startRead) | `P:LegadoUI/RemoteBookView.swift:55-60,64-86,98-160,213-224` — no server config, no search, no select-all, no help, no log, no tap-to-read | Partial |
| Local books: mobi / azw3 are recognised book formats | `U:constant/AppPattern.kt:28` (`bookFileRegex = .*\.(txt\|epub\|umd\|pdf\|mobi\|azw3\|azw)`) | `P:LegadoCore/Local/LocalBookScanner.swift:87-90` `isSupportedBook` = ["txt","epub","umd","pdf"] (the scanner skips mobi even though `P:LegadoCore/Local/Mobi/MobiLocalBook.swift` can read it); `P:LegadoUI/LocalBookView.swift:137-145` the same list | Partial |
| Local books: open one book inside a zip archive without adding the whole archive to the shelf | `U:ui/book/import/BaseImportBookActivity.kt:89-101` (`onArchiveFileClick` → the per-file selector), `U:model/localBook/LocalBook.kt:274` (`importArchiveFile`) | `P:LegadoCore/App/LocalBookImporter.swift:164-204` imports every book inside; `P:LegadoUI/LocalBookBrowserView.swift:363-374` only 加入书架 | Partial |

## Android-only items that must NOT be ported

- **PROCESS_TEXT intent** entries in the selection menu (`U:ui/book/read/TextActionMenu.kt`) — an Android service hook; the port's 8 actions in `P:LegadoUI/SelectionOverlay.swift` are complete.
- **`sysTtsConfig` → `IntentHelp.openTTSSetting`** (`RES:xml/pref_config_aloud.xml`) — opens the Android TTS settings; iOS lists the `AVSpeechSynthesizer` voices (`P:LegadoUI/ReadAloudPlatform.swift`).
- **到后台 (`ll_to_backstage` → `activity.finish()`)** — an iOS app must never quit the user.
- **`createHeapDump` / `recordHeapDump`** (`U:ui/about/AboutFragment.kt:143-165`) — an ART heap dump, no iOS equivalent.
- **Cronet / `process_text` / 清除网页数据 (the Android WebView)** — Android networking and WebView internals.
- **Play Store 评分 (`menu_scoring`)** — an iOS build rates the App Store.
- **邮件 (`sendMail`) + 公众号 clipboard** (`U:ui/about/AboutFragment.kt:61,65`) — Android intents / WeChat-only; the port keeps the GitHub contributors link and the four md documents.
- **`customPageKey` / PageKeyDialog** (`U:ui/book/read/config/PageKeyDialog.kt:1-75`) — the Android prev/next hardware key codes.
- **logcat capture** in 保存日志 (`U:ui/about/AboutFragment.kt:167-187`).
- **退出 (exit)** in `RES:xml/pref_main.xml` — no quit button on iOS.
- **The WebView help viewer** (`RES:assets/web/help/index.html` + the md assets) — the port renders the same documents natively (`P:LegadoUI/AboutDocuments.swift` + `MarkdownView`).

## Verdict

The port is strongest where it counts most for daily use: the text-selection action menu (all 8
actions, 更多 toggle, the long-press mode switch), the read-aloud *configuration* (every
`pref_config_aloud` toggle, the rate, the timer choices, the engine list, the spoken-sentence
highlight, the click-region read-aloud actions), the whole TOC screen (both tabs, the search, the
reverse, 使用替换, 显示字数, 分割长章节, the bookmark export JSON/MD, the log), the reader
style/preference screens, the theme / cover / welcome / other-settings / backup-WebDAV /
direct-link-upload / source-check configuration, the reading record and the about page (the
contributors, the update log, the licence, the disclaimer, the privacy policy, the crash log, the
update check).

The gaps cluster in three places:

- **(a) the read-aloud management layer** — no per-book engine, no import/export/delete/login for the
  HTTP TTS engines, several editor fields unused, and the panel lacks the chapter jumps and the live
  timer;
- **(b) the rule-management screens** (the dictionary rules, the TXT TOC rules) that expose only a
  subset of the upstream menus (no QR import, no delete, no bulk enable/disable, no drag reorder, no
  help/copy-paste) even though the underlying Core model supports them;
- **(c) the 我的/config layer**, where the Web-service address is computed but never shown, the file
  manager is not a file browser, the WebDAV remote-book screen is reduced, "删除原文件" is a no-op, the
  delete confirmation is skipped, the webFile / WebDAV-remote book import is absent, and several minor
  about-page items (the crash-log clear, the zipped log, the share/rate, the app help) are missing.

The remaining upstream screens (the local-book import browser, the book export, the rule
import/export for the sources and the replace rules) are fully ported.
