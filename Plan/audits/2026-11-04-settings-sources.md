# The audit of 2026-11-04 — the settings screens + the source management

Upstream = `D:\code\vscode\legado`, the port = `D:\code\vscode\legado-ios`.
**The preference-KEY layer is complete** — a diff of all 182 upstream `PreferKey.kt` values against the port's
`SettingsKey` found 0 missing keys (the port even adds the upstream's non-PreferKey XML keys).
Every gap below is a UI/behaviour gap.

## A. 关于 / About (`ui/about/`)

1. The 贡献者 row (the contributors URL) — upstream `AboutFragment.kt:58`. The port's `MineViews.swift:443-514` has none.
2. The 更新日志 row (the `updateLog.md` asset) — upstream `AboutFragment.kt:59`. Missing.
3. The 隐私政策 / 开源许可 / 免责声明 documents — upstream `AboutFragment.kt:62-64`. Missing (the files are not in the port).
4. The 崩溃日志 row (`CrashLogsDialog`) — upstream `AboutFragment.kt:66`. Missing.
5. 保存日志 (zips the logs into `logs.zip`) — upstream `AboutFragment.kt:67`. Missing.
6. 生成堆转储 — upstream `AboutFragment.kt:68`. Android-only.
7. The about menu (share the app) — upstream `AboutActivity.kt:52-57`. Missing.
8. The update dialog renders the release body as **Markdown** — upstream `UpdateDialog.kt:36`.
   The port's `MineViews.swift:476-483` uses a plain `Text`.

## B. 阅读记录 (`ui/about/ReadRecordActivity.kt`) — the port's `MineViews.swift:232-260`

9. The search of the records — upstream `:44,115-120`. Missing.
10. 删除 (clear all the records) — upstream `:101-105`. Missing.
11. The sort menu (name / read length / read time) — upstream `:73-97`. Missing.
12. `menu_enable_record` (`AppConfig.enableReadRecord`) — upstream `:91-97`. The key + accessor exist
    (`AppSettings.swift:177,928`) but there is NO UI and nothing reads it.
13. The total reading time — upstream `:133-136`. Missing.
14. Tapping a record opens the book — upstream `:185-190`. Missing.
15. The per-row 删除 — upstream `:198-210`. Missing.

## C. 主题设置 (`ui/config/ThemeConfigFragment.kt`)

16. Pick the day/night **background image** — upstream `:197-198,238-274,339-357`. The keys exist
    (`AppSettings.swift:194-195`) but NOTHING reads them; `AppTheme` has no background-image field.
17. The background-image **blurring** slider (`bgImageBlurring` / `bgImageNightBlurring`) — upstream `:276-302`. Missing.
18. The 8 colour preferences (`colorPrimary`/`colorAccent`/`colorBackground`/`colorBottomBackground` + the 4 night keys)
    with the validation (the day background must not be dark) — upstream `:83-99,144-156`. The upstream preference
    keys are NEVER written (the port edits an `AppTheme` inside the theme list instead).
19. barElevation (0..32 + 默认) — upstream `:169-181`. Missing.
20. The fontScale row with a 默认 (0) reset — upstream `:183-195`. The port's `SettingsView.swift:139` has an 8..16 Picker.

## D. 其它设置 (`ui/config/OtherConfigFragment.kt`)

21. 清除网页数据 — upstream `:157`. Missing.
22. 压缩数据库 (`VACUUM`) — upstream `:159`. Missing (the port uses SQLite).
23. 记录日志 (the log level + the log file) — upstream `:187-194`. The key exists but the port's `AppLog` is memory-only.
24. 预下载数 (0..9999) — upstream `:96-103`. The accessor exists (`AppSettings.swift:566-570`) but is NEVER used:
    `Core/Reader/ReadBook.swift:111,201` hard-codes `preDownloadCount = 1`.
25. 缓存大小 / 图片保留数 — upstream `:126-144`. Missing.
26. 书源编辑最大行数 — upstream `:146-155`. The key exists, is unused; the rule editor has no limit.
27. 默认书籍目录 (the folder picker) — upstream `:91`. Missing.
28. 自动刷新 (`autoRefreshBook`) — upstream `pref_config_other.xml:21`. The accessor exists but is never used; no row.
29. 打开时直接阅读 (`defaultToRead`) — the BEHAVIOUR exists (`AppModel.swift:1102`), no row.
30. 漫画模式 (`showMangaUi`) — the BEHAVIOUR exists (`AppModel.swift:1071`), no row.
31. 加入书架时提示 (`showAddToShelfAlert`) — upstream `ReadBookActivity.kt:1599`. Missing.
32. 自动清除过期缓存 (`autoClearExpired`) — upstream `App.kt:103`. Missing.
33. 默认替换规则 (`replaceEnableDefault`) — upstream `Book.kt:209`. Missing.
34. 朗读时响应媒体按键 / 退出时响应媒体按键 — upstream `pref_config_other.xml:138,131`. Missing.
35. 默认首页 (`defaultHomePage`) — the port always starts on the 书架 tab (`RootView.swift:33-56`).
36. 语言 (`language`) — the port is Chinese-only (no localisation infra).

## E. 备份与恢复 (`ui/config/BackupConfigFragment.kt`) — the port's `BackupView.swift`

37. **The WebDAV URL / account / password are NEVER persisted** — upstream `:109-141`. The port's `BackupView.swift:79-81`
    keeps them in `@State` and never writes them back; the setters (`AppSettings.swift:874-888`) have NO caller.
    ⇒ the credentials are lost when the screen closes and the WebDAV progress sync always answers "未配置 WebDAV".
    **THE HIGHEST-IMPACT FUNCTIONAL BUG.**
38. The WebDAV directory (`webDavDir`, default "legado") — upstream `:118-123`. `BackupView.swift:428` hard-codes `backupDirectory: ""`.
39. The WebDAV device name — upstream `:124-129`. Read at `BackupView.swift:405` but there is no row to edit it.
40. 同步进度 / 同步进度+章节内容 (`syncBookProgress` / `syncBookProgressPlus`) — upstream `pref_config_backup.xml:46,56`.
    The accessors exist (`AppSettings.swift:860-871`) but are never read ⇒ the progress sync is not gated and the
    "sync the chapter content too" behaviour is missing (`ReadBookActivity.kt:356-371`).
41. 自动检查新备份 — upstream `pref_config_backup.xml:110`. Missing.
42. The backup-screen menu (menu_help → `webDavHelp.md` + menu_log → `AppLogDialog`) — upstream `:159-169`.
    The port's `BackupView` has no toolbar; the asset `Sources/LegadoServer/Resources/WebUI/help/md/webDavHelp.md` exists
    but is never displayed.
43. 长按恢复 → pick a zip from anywhere — upstream `:136-140,335-389`. The port only lists the zips of the backup directory.

## F. 封面设置 (`ui/config/CoverConfigFragment.kt`)

44. The default cover cannot be deleted (only 选择日间封面 / 选择夜间封面) — upstream `:100-153`.
45. 显示作者 is enabled only while 显示书名 is on — upstream `:50-53,80-89`. The port's two toggles are independent.

## G. 启动页样式 (`ui/config/WelcomeConfigFragment.kt`)

46. The `customWelcome` master switch — upstream `pref_config_welcome.xml:7`. The key exists (`AppSettings.swift:215`), unused.
47. **The whole feature is inert** — the port's `WelcomeView.swift:32-51` never reads `welcomeImagePath` /
    `welcomeShowText` / `welcomeShowIcon` ⇒ the image the user picks NEVER appears.
48. 删除启动图 (deleting also resets the toggles to true) — upstream `:111-142,144-175`. Missing.

## H. 书源管理 (`ui/book/source/manage/BookSourceActivity.kt`)

49. Drag-to-reorder (`BookSourceAdapter.swap()`, `customOrder`) — MISSING in the port.
50. `menu_check_selected_interval` — upstream `:493`. Missing (the port has only 校验所选).
51. The per-row 搜索该源 (`searchBook`) — upstream `:154,638`. Missing.
52. After a check, a group containing "失效" auto-filters the list — upstream `:154,638`. Missing.
53. `menu_export_selection` writes a FILE — upstream `:468`. The port copies the JSON to the pasteboard only.
54. The import-from-URL history (ACache `bookSourceRecordKey`) — upstream `:183,587-615`. Missing.

## I. 书源编辑 (`ui/book/source/edit/BookSourceEditActivity.kt`)

55. The 书源类型 (text/audio/image/file) selector — upstream `:252-259,378-383`. The model supports it, the editor has no field.
56. 封面解码 (coverDecodeJs) / 书籍地址正则 (bookUrlPattern) / 变量说明 (variableComment) — upstream `:264-277`.
    The model supports them but the book-source editor has no fields.
57. `menu_search` — search the books with this source from the editor. Missing.
58. `menu_qr_code_camera` — import a source by QR from the editor. Missing.
59. The confirmation before leaving the editor with unsaved changes — upstream `:213-226`. Missing.
60. The help actions (插入URL参数 / 书源教程 / js教程 / 正则教程 / 插入分组 / 选择文件) — upstream `:587-624`.
    The assets `jsHelp.md` / `regexHelp.md` / `SourceMBookHelp.md` exist under
    `Sources/LegadoServer/Resources/WebUI/help/md/` but are never shown in the app.

## J. 直链上传 (`ui/config/DirectLinkUploadConfig.kt`)

61. 导入默认 always applies the rule at index 0 — the chooser over the three defaults is missing.
62. 测试 shows the result inline (no dialog, no 复制文本) — upstream.

## The Android-only items (deliberate deviations — do not fix)

- process_text (the Android context-menu receiver), Cronet, recordHeapDump, transparentStatusBar / immNavigationBar,
  updateToVariant, webServiceWakeLock, the Play Store rating, the Android DownloadManager APK install,
  the "退出" preference (an iOS app must not terminate itself).
