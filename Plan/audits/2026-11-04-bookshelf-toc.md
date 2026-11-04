# The audit of 2026-11-04 — the bookshelf / the book info / the TOC / the groups / the book tools

Upstream = `D:\code\vscode\legado` (`app/src/main/java/io/legado/app/…`), the port = `D:\code\vscode\legado-ios`.
Only the genuinely missing or broken features are listed; the Android-only items are at the end.

## A. The bookshelf + the bookshelf management

1. **The group filter submenu is unreachable** — upstream `ui/book/manage/BookshelfManageActivity.kt:316-323`
   (the `menu_book_group` submenu) + `:276-280`. The port's `BookshelfManageView.swift:218-239` filters by
   `groupFilterId` but nothing ever sets it.
2. **"点击书名打开书籍详情" is a dead toggle and the title is not tappable** — upstream
   `BookshelfManageActivity.kt:139-144,271-273` + `ui/book/manage/BookAdapter.kt:89-95`.
   The port's `BookshelfManageView.swift:102-104` only READS `openBookInfoByClickTitle`; the row renders a plain `Text`.
3. **"分组管理" in the bookshelf-management menu is a no-op** — upstream `BookshelfManageActivity.kt:270`
   → `GroupManageDialog`. The port's `BookshelfManageView.swift:96-98` closes the sheet and does nothing.
4. **The export of the used book sources produces no file** — upstream `BookshelfManageActivity.kt:274-280`
   → `saveAllUseBookSourceToFile` → "bookSource.json". The port's `BookshelfManageView.swift:379-385` only
   copies the JSON to the pasteboard.
5. **The batch 换源 does not migrate the reading progress and has no per-book delay** — upstream
   `ui/book/manage/BookshelfManageViewModel.kt:83` (`book.migrateTo(newBook, toc)`) +
   `AppConfig.batchChangeSourceDelay` (`ui/book/manage/SourcePickerDialog.kt:101-119`). The port's
   `BookshelfManageView.swift:345-375` never calls `migrateTo`; the delay key has no accessor and no UI.
   The upstream's picker lists only the ENABLED sources (`SourcePickerDialog.kt:87-99`); the port lists all.
6. **The delete confirmation has no "同时删除本地文件" checkbox** — upstream `BookshelfManageActivity.kt:325-342`
   (`LocalConfig.deleteBookOriginal`). The port's `BookshelfManageView.swift:161-168` has only OK/Cancel.
7. **"检查所选区间" selects to the END of the list instead of min…max** — upstream
   `ui/book/manage/BookAdapter.kt:136-153`. The port's `BookshelfManageView.swift:262-267`.
8. **The per-row group button and the group names in the row are missing** — upstream
   `ui/book/manage/BookAdapter.kt:52-63,101-106`. The port's `BookshelfManageView.swift:175-209` shows no group
   name and the per-row 移动到分组 applies to the whole selection.
9. **The "文件夹" bookshelf style is only a chip strip** — upstream `ui/main/bookshelf/style2/BookshelfFragment2.kt`
   (the nested navigation, the group cover, the long press → `GroupEditDialog`). The port's
   `BookshelfView.swift:319-369` is a horizontal chip strip.
10. **The group cover image is missing (not even in the model)** — upstream
    `ui/book/group/GroupEditDialog.kt:39-57,68-101` (`coverPath`). The port's `BookGroup` has no `cover`.
11. **The 64-group limit is missing** — upstream `ui/book/group/GroupManageDialog.kt:95-99`.
12. **A second, weaker group manager is exposed in the settings** — the port's
    `ManageViews.swift:578-622` `BookGroupView` (add/delete only) vs. `BookshelfToolsViews.swift:32-139`.
13. **The local-book import screen lacks the sort, the batch multi-select and the JS file-name rule** — upstream
    `ui/book/import/local/ImportBookActivity.kt:84-129,272-285` (`AppConfig.bookImportFileName`).

## B. The book info

14. **The all-bookmarks screen cannot export and cannot edit a bookmark** — upstream
    `ui/book/bookmark/AllBookmarkActivity.kt:37-38,67-79`. The port's `ManageViews.swift:533-573` — list + delete only.
15. **The full-screen cover view (the long press) is missing** — upstream `ui/book/info/BookInfoActivity.kt:431-436`
    → `PhotoDialog`. The port's `BookDetailView.swift:215` has a plain image.
16. **"更换封面" only accepts a typed URL** — upstream `BookInfoActivity.kt:424-430` +
    `ui/book/changecover/ChangeCoverDialog.kt:66-69,101-106` (the grid of the covers the sources provide).
    The port's `BookshelfManageView.swift:760-789` has a single text field.
17. **Tapping the source name does not open the source editor** — upstream `BookInfoActivity.kt:463-474`.
    The port's `BookDetailView.swift:234-242` opens the LOGIN instead.
18. **Tapping the author / the name does not search** — upstream `BookInfoActivity.kt:504-517`.
    The port's `BookDetailView.swift:217-221` renders plain `Text`.
19. **"复制目录链接" copies the book URL, not the TOC URL** — upstream `BookInfoActivity.kt:240-242` (`book.tocUrl`).
    The port's `BookDetailView.swift:139-141` copies `current.bookUrl`. **BUG.**
20. **"删除提示" (the confirmation before removing the book) is missing** — upstream
    `BookInfoActivity.kt:199,268` (`LocalConfig.bookInfoDeleteAlert`). The key does not exist in the port.
21. **"拆分长章节" is missing from the book-info menu** — upstream `BookInfoActivity.kt:185,195,258-266`
    (a local TXT book only).
22. **"上传到远程" (a local book → WebDAV) is missing** — upstream `BookInfoActivity.kt:197,269-283`.
23. **"日志" is missing from the book-info menu** — upstream `BookInfoActivity.kt:257` → `AppLogDialog`.
    The port's `AppLogView.swift` is not reachable from the book detail.
24. **The share dialog has no QR code** — upstream `BookInfoActivity.kt:214-220` (`shareWithQr`).
    The port's `BookDetailView.swift:154-156` shares the text only (the QR exists in `QRCodeView`).
25. **The book-info editor has no 书籍类型 and no local-image cover** — upstream
    `ui/book/info/edit/BookInfoEditActivity.kt:81-92,99-142,150-169`.

## C. The table of contents

26. **"当前章节 n/N" is not clickable** — upstream `ui/book/toc/ChapterListFragment.kt:86-87`
    (it scrolls the list to the current chapter). The port's `TocView.swift:83-96` is a plain `Text`.
27. **"使用替换" never writes the global setting** — upstream `ui/book/toc/TocActivity.kt:127-171`
    (`AppConfig.tocUiUseReplace`). The port's `TocView.swift:312` reads it but `:351-357` flips `book.useReplaceRule`.
28. **"显示字数" is not persisted** — upstream `TocActivity.kt` (`AppConfig.tocCountWords`).
    The port's `TocView.swift:46-47` keeps it in a local `@State`.
29. **The TOC bookmark rows show neither the bookmarked text nor the content** — upstream
    `ui/book/toc/BookmarkAdapter.kt:25-41`. The port's `TocView.swift:63-79`.

## D. The book tools

30. **The cache screen is missing almost every export option** — upstream
    `ui/book/cache/CacheActivity.kt:204-219` (导出全部 / 启用替换 / 自定义导出 / 不导出章节名 / 导出到WebDAV /
    导出图片文件 / 并行导出 / 导出目录 / 导出文件名 / 导出格式 / 导出字符集 / 日志) + `:358-472` (the custom
    EPUB section export). The port's `DownloadViews.swift:122-141` has only 全部缓存 / 全部停止 / 日志, and the
    per-row export is always TXT although the engine supports EPUB.
31. **The cache screen has no group filter** — upstream `CacheActivity.kt:160-163,220-224`.
32. **The 换源 dialog is missing most of the search options** — upstream
    `ui/book/source/ChangeBookSourceDialog.kt:130-142,272-317,408-432` (加载详情 / 加载目录 / 开始停止 /
    书源管理 / 刷新列表 / the group submenu) + `ui/book/source/ChangeBookSourceAdapter.kt` (the per-result
    long-press menu, the 好/坏 scoring, the response time). The port's `BookToolsViews.swift:29-132` has only
    校验作者 + 加载字数.

## The Android-only items (no iOS equivalent is needed)

- The SAF export/import (`HandleFileContract`) — the port writes into the cache-storage root and/or the pasteboard.
- The import folder tree — the port uses the document picker + `LocalBookScanner.scan`.
- `DragSelectTouchHelper` slide-select — the port uses per-row checkboxes.
- The TOC 顶部/底部 buttons scroll the list; the port opens the reader at that chapter (acceptable).
