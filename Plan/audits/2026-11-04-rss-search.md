# The audit of the RSS, the discover and the search (2026-11-04)

The fourth audit of the port — the RSS (the sources, the articles, the
favourites), the discover and the search. The audit only reports what is
genuinely missing or partially implemented; the Android-only items are listed
separately. Nothing was modified by the audit.

## The functional bugs (they were broken, not merely missing)

| # | The finding | The port | The upstream |
|---|---|---|---|
| 1 | The RSS source list includes the disabled sources | `Sources/LegadoUI/RSSView.swift:219-222` (all `model.rssSources`) | `RssSourceDao` filters `enabled = 1` |
| 2 | The RSS read records are written but never listed or cleared | `AppModel.markRead(_:)` → `Core/App/RssLibrary.swift` → the `rssReadRecords` table; no screen exists | `ui/rss/article/ReadRecordDialog.kt` + `RssSortViewModel.getRecords/countRecords/deleteAllRecord` |
| 3 | The RSS source has no login | `AppModel.loginSource: BookSource?` — the login is book-source only | `SourceLoginActivity` with the type `rssSource` |
| 4 | The RSS article screen has no menu at all | `Sources/LegadoUI/RSSView.swift:71-92` | `ui/rss/article/RssSortActivity.kt:57-99` + `res/menu/rss_articles.xml` (seven entries) |
| 5 | The RSS reader has no share and no read aloud | `Sources/LegadoUI/RssArticleReaderView.swift:68-81` | `ui/rss/read/ReadRssActivity.kt` |
| 6 | The RSS favourites cannot be edited (the title, the group) | `Sources/LegadoUI/RSSView.swift:387-535` | `ui/rss/manager/RssStarDialog` |
| 7 | The RSS import has no preview dialog | `Sources/LegadoUI/RssSourceManagementView.swift:520-551` | `ui/rss/manager/RssSourceImportDialog` |
| 8 | The RSS source debugger has no UI | `Core/Pipeline/Debug.swift:355` (`SourceDebugger.debugRssSource`) exists but is unreachable | `ui/rss/manager/RssSourceDebugFragment` |
| 9 | The search pagination is dead code | `Sources/LegadoUI/SearchView.swift:296-316` (`private func loadMore()` is never called) | `ui/book/search/SearchActivity.kt:345-355` (`scrollToBottom()` → `viewModel.search("")`) |
| 10 | The discover ignores `enabledExplore` | `Sources/LegadoUI/DiscoverView.swift:287-300` (only the empty `exploreUrl` is tested) | `BookSourceDao.flowExplore` (enabledExplore = 1 AND hasExploreUrl = 1) |
| 11 | The discover group list uses the groups of ALL the sources | `Sources/LegadoUI/DiscoverView.swift:303-311` | `BookSourceDao.flowExploreGroupsUnProcessed` |
| 12 | The discover filter does not match the group | `Sources/LegadoUI/DiscoverView.swift:296-299` (only the name and the URL) | `flowExplore(key)` — the group or the name contains the key |

## The missing features

### The RSS (19)

1. The article-screen menu: 登录 / 刷新排序 / 源变量 / 编辑源 / 切换布局 / 阅读记录 / 清除.
2. The article layouts: the upstream has three (`articleStyle` 0 = the list, 1 = the compact row with the image on the left, 2 = the grid with two columns).
3. The read-record screen (`ReadRecordDialog`).
4. 清除 — the cached articles of the URL (`RssArticleDao.delete`).
5. The variable editor of the RSS source (the `VariableDialog`).
6. The login of the RSS source.
7. The RSS source debugger.
8. The toolbar of the RSS editor (only 保存 is there).
9. The favourite editor (the title, the group).
10. The share and the read aloud of the RSS reader.
11. Saving an image in the RSS web view.
12. The image, the grid and the read state of the article row.
13. The search of the RSS source list.
14. The long-press menu of the RSS source list.
15. The "only the enabled sources" filter.
16. `singleUrl` — a source with a single article.
17. 分享选中源.
18. 检查选中源定时.
19. The preview dialog of the RSS import + 帮助 + the drag reorder of the rule subscriptions.

### The discover and the search (13)

1. The dynamic scope quick-switch menu.
2. 日志.
3. The 精准搜索 toggle does not re-run the search.
4. The second branch of the empty-result dialog ("切换到全部分组？").
5. The chips with the books of the shelf.
6. The cover, the number of origins, the latest chapter and the kind of the search row.
7. The separate ExploreShow screen.
8. The "ERROR:" category dialog.

## The Android-only items

- The PROCESS_TEXT intents of the browser.
- The volume-key paging.
- The Android-TV `PageKeyDialog`.
- `sysTtsConfig` (the system TTS settings intent).
