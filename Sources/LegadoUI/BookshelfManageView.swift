//
//  BookshelfManageView.swift
//  LegadoUI
//
//  The bookshelf batch management and the book information menu.
//
//  Upstream `ui/book/manage/BookshelfManageActivity.kt` (377 lines) lists the
//  books of the shelf with a multi-selection and offers the batch actions
//  (the delete, the update of the table of contents, the move to a group,
//  the cache and the source switch). `ui/book/info/BookInfoActivity.kt` has
//  the book menu (the metadata editor, the share, the pin, the variables,
//  the cover, the group and the delete).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit)
// SwiftUI re-exports UIKit on Apple platforms, but the stub module of the
// Linux type check does not — the import is explicit.
import UIKit
#endif

// MARK: - The bookshelf batch management

/// The bookshelf batch management — upstream `BookshelfManageActivity`.
///
/// The upstream screen (upstream `app/src/main/java/io/legado/app/ui/book/manage/BookshelfManageActivity.kt`)
/// has a search field, a group submenu, the drag reorder (only for the manual
/// sort), the select all / clear / invert actions, the range selection and the
/// batch actions: delete (with the "delete the book file" checkbox), enable /
/// disable the update, add to a group, move to a group, change the source,
/// clear the cache and export the sources the books use.
public struct BookshelfManageView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var books: [Book] = []
    @State private var allBooks: [Book] = []
    @State private var selection: Set<String> = []
    @State private var message: String?
    @State private var isGroupPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var isDeleteConfirmed = false
    @State private var deleteOriginal = false
    @State private var filter = ""
    @State private var groupFilterId: Int64 = BookGroup.Id.all
    /// The anchor of the range selection (upstream
    /// `BookAdapter.checkSelectedInterval`).
    @State private var rangeAnchor: String?
    @State private var isReordering = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                ForEach(books, id: \.bookUrl) { book in
                    row(book)
                }
                .onMove { source, destination in
                    move(from: source, to: destination)
                }
            } header: {
                Text("已选 \(selection.count) / \(books.count)")
            }
        }
        .navigationTitle("书架管理")
        .searchable(text: $filter)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("全选") {
                        selection = Set(books.map(\.bookUrl))
                    }
                    Button("取消") {
                        selection.removeAll()
                        rangeAnchor = nil
                    }
                    Button("反选") {
                        invertSelection()
                    }
                    Button("检查所选区间") {
                        selectInterval()
                    }
                    Divider()
                    Button("分组管理") {
                        isGroupPickerPresented = false
                    }
                    Button("导出用到的书源") {
                        exportUsedSources()
                    }
                    Button("点击书名打开书籍详情") {
                        model.environment.settings.bool(.openBookInfoByClickTitle, default: false)
                    }
                } label: {
                    Text("更多")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("删除") {
                    deleteOriginal = model.environment.localConfig.deleteBookOriginal
                    isDeleteConfirmed = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("更新目录") {
                    updateSelected()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("移动分组") {
                    isGroupPickerPresented = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("允许更新") {
                        setCanUpdate(true)
                    }
                    Button("禁止更新") {
                        setCanUpdate(false)
                    }
                    Button("加入分组") {
                        isGroupPickerPresented = true
                    }
                    Button("换源") {
                        isSourcePickerPresented = true
                    }
                    Button("清除缓存") {
                        clearCache()
                    }
                } label: {
                    Text("批量")
                }
            }
        }
        .sheet(isPresented: $isGroupPickerPresented) {
            NavigationStack {
                GroupPickerView(model: model) { groupId in
                    moveSelected(to: groupId, replace: true)
                }
            }
        }
        .sheet(isPresented: $isSourcePickerPresented) {
            NavigationStack {
                SourcePickerView(model: model) { source in
                    changeSource(to: source)
                }
            }
        }
        .alert("删除", isPresented: $isDeleteConfirmed) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("确定要删除选中的 \(selectedBooks.count) 本书吗？")
        }
        .onAppear {
            reload()
        }
    }

    /// One row of the list.
    private func row(_ book: Book) -> some View {
        HStack {
            Button {
                toggle(book)
            } label: {
                Text(selection.contains(book.bookUrl) ? "☑" : "☐")
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.name)
                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if !book.originName.isEmpty {
                    Text(book.originName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("移动到分组") {
                    isGroupPickerPresented = true
                }
                Button("删除") {
                    selection = [book.bookUrl]
                    deleteOriginal = model.environment.localConfig.deleteBookOriginal
                    isDeleteConfirmed = true
                }
            } label: {
                Text("更多")
                    .font(.system(size: 13))
            }
        }
    }

    private func reload() {
        allBooks = (try? model.environment.store.allBooks()) ?? []
        applyFilter()
    }

    /// Applies the search field and the group filter — upstream
    /// `BookshelfManageActivity.upBookData`.
    private func applyFilter() {
        var result = allBooks
        if groupFilterId != BookGroup.Id.all {
            if groupFilterId > 0 {
                result = result.filter { ($0.group & groupFilterId) > 0 }
            } else {
                result = result.filter { $0.group == 0 }
            }
        }
        let keyword = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            result = result.filter { book in
                book.name.contains(keyword)
                    || book.author.contains(keyword)
                    || book.originName.contains(keyword)
                    || book.origin.contains(keyword)
                    || (book.kind?.contains(keyword) == true)
                    || (book.intro?.contains(keyword) == true)
            }
        }
        books = result
    }

    private func toggle(_ book: Book) {
        rangeAnchor = nil
        if selection.contains(book.bookUrl) {
            selection.remove(book.bookUrl)
        } else {
            selection.insert(book.bookUrl)
        }
    }

    /// Inverts the selection — upstream `BookAdapter.revertSelection`.
    private func invertSelection() {
        var next = Set<String>()
        for book in books where !selection.contains(book.bookUrl) {
            next.insert(book.bookUrl)
        }
        selection = next
        rangeAnchor = nil
    }

    /// Selects the books between the anchor and the tapped book — upstream
    /// `BookAdapter.checkSelectedInterval`.
    private func selectInterval() {
        guard let first = selection.first,
              let start = books.firstIndex(where: { $0.bookUrl == first }) else { return }
        let end = books.count - 1
        selection = Set(books[start...end].map(\.bookUrl))
    }

    private var selectedBooks: [Book] {
        books.filter { selection.contains($0.bookUrl) }
    }

    /// Deletes the selected books — upstream
    /// `BookshelfManageViewModel.deleteBook`.
    ///
    /// The local books also lose their file when the "delete the book file"
    /// box is ticked (upstream `LocalConfig.deleteBookOriginal`).
    private func deleteSelected() {
        model.environment.localConfig.deleteBookOriginal = deleteOriginal
        for book in selectedBooks {
            try? model.environment.deleteBook(book)
            if deleteOriginal, BookType.contains(book.type, BookType.local) {
                model.environment.cacheStorage?.clearCache(book: book)
            }
        }
        selection.removeAll()
        reload()
        model.reloadBookshelf()
        message = "已删除"
    }

    private func updateSelected() {
        Task {
            var updated = 0
            for book in selectedBooks {
                let result = await model.updateBook(book)
                if result?.isSuccess == true { updated += 1 }
            }
            reload()
            message = "已更新 \(updated) 本"
        }
    }

    /// Allows or forbids the update — upstream
    /// `BookshelfManageViewModel.upCanUpdate`.
    private func setCanUpdate(_ canUpdate: Bool) {
        for book in selectedBooks {
            var changed = book
            changed.canUpdate = canUpdate
            if !canUpdate {
                changed.type = changed.type & ~BookType.updateError
            }
            try? model.environment.store.update(changed)
        }
        reload()
        model.reloadBookshelf()
    }

    /// Moves the selected books to a group — upstream
    /// `BookshelfManageActivity.upGroup`.
    ///
    /// The "移动分组" action REPLACES the group mask, the "加入分组" action
    /// ORs it into it.
    private func moveSelected(to groupId: Int64, replace: Bool) {
        for book in selectedBooks {
            var changed = book
            changed.group = replace ? groupId : (changed.group | groupId)
            try? model.environment.store.update(changed)
        }
        reload()
        model.reloadBookshelf()
    }

    /// Clears the cache of the selected books — upstream
    /// `BookshelfManageViewModel.clearCache`.
    private func clearCache() {
        for book in selectedBooks {
            model.environment.cacheStorage?.clearCache(book: book)
        }
        message = "已清除缓存"
    }

    /// Changes the source of the selected books — upstream
    /// `BookshelfManageViewModel.changeSource`.
    private func changeSource(to source: BookSource) {
        Task {
            var changed = 0
            for book in selectedBooks {
                if BookType.contains(book.type, BookType.local) { continue }
                if book.origin == source.bookSourceUrl { continue }
                guard let found = try? await WebBook.preciseSearch(
                    bookSource: source,
                    name: book.name,
                    author: book.author,
                    dependencies: model.environment.dependencies()
                ) else { continue }
                var newBook = found
                if newBook.tocUrl.isEmpty {
                    guard let info = try? await model.environment.loadBookInfo(book: newBook, source: source) else {
                        continue
                    }
                    newBook = info
                }
                guard let chapters = try? await model.environment.loadChapterList(book: newBook, source: source) else {
                    continue
                }
                try? model.environment.store.insert(newBook)
                try? model.environment.store.insert(chapters.chapters)
                changed += 1
            }
            reload()
            model.reloadBookshelf()
            message = "已换源 \(changed) 本"
        }
    }

    /// Exports the sources the books use — upstream
    /// `BookshelfManageViewModel.saveAllUseBookSourceToFile`.
    private func exportUsedSources() {
        let urls = Set(selectedBooks.map(\.origin))
        let used = model.sources.filter { urls.contains($0.bookSourceUrl) }
        let json = JSONValue.array(used.map { BookSourceJSONBridge.encode($0) }).jsonString
        message = "已导出 \(used.count) 个书源"
        UIPasteboardShim.copy(json)
    }

    /// Reorders the books — upstream `ItemTouchCallback`.
    private func move(from source: IndexSet, to destination: Int) {
        guard let first = source.first, first >= 0, first < books.count else { return }
        var moved = books
        let book = moved.remove(at: first)
        let target = min(max(destination, 0), moved.count)
        moved.insert(book, at: target)
        for (index, item) in moved.enumerated() {
            var changed = item
            changed.order = Int64(index)
            try? model.environment.store.update(changed)
        }
        books = moved
    }
}

/// The source picker — upstream `SourcePickerDialog`.
struct SourcePickerView: View {

    @ObservedObject var model: LegadoAppModel
    let onSelect: (BookSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    public init(model: LegadoAppModel, onSelect: @escaping (BookSource) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            ForEach(filteredSources, id: \.bookSourceUrl) { source in
                Button {
                    onSelect(source)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.bookSourceName)
                        Text(source.bookSourceUrl)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .searchable(text: $filter)
        .navigationTitle("选择书源")
    }

    private var filteredSources: [BookSource] {
        let keyword = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return model.sources }
        return model.sources.filter {
            $0.bookSourceName.contains(keyword) || $0.bookSourceUrl.contains(keyword)
        }
    }
}

/// The group picker — upstream `ManageGroupActivity` / the group popup.
struct GroupPickerView: View {

    @ObservedObject var model: LegadoAppModel
    let onSelect: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel, onSelect: @escaping (Int64) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            ForEach(model.groups, id: \.groupId) { group in
                Button(group.groupName) {
                    onSelect(group.groupId)
                    dismiss()
                }
            }
        }
        .navigationTitle("选择分组")
    }
}

// MARK: - The book information menu

/// The book information menu — upstream `BookInfoActivity`'s menu.
public struct BookInfoMenuView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var isEditing = false
    @State private var isSharePresented = false
    @State private var message: String?
    /// The variable editor (the source variable or the book variable).
    @State private var variableKind: VariableKind?
    /// The cover editor.
    @State private var isCoverPresented = false

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        List {
            Section("书籍") {
                LabeledRow(title: "书名", value: book.name)
                LabeledRow(title: "作者", value: book.author)
                if let intro = book.displayIntro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 13))
                }
            }
            Section("操作") {
                Button("编辑") {
                    isEditing = true
                }
                Button("分享") {
                    isSharePresented = true
                }
                Button("复制链接") {
                    UIPasteboardShim.copy(book.bookUrl)
                    message = "已复制"
                }
                Button("置顶") {
                    pin()
                }
                Button("源变量") {
                    variableKind = .source
                }
                Button("书籍变量") {
                    variableKind = .book
                }
                Button("更换封面") {
                    isCoverPresented = true
                }
                Button("删除") {
                    delete()
                }
            }
            if let message {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("书籍信息")
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                BookMetadataEditor(book: book) { updated in
                    try? model.environment.store.update(updated)
                    model.reloadBookshelf()
                }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [book.bookUrl])
        }
        .sheet(item: $variableKind) { kind in
            NavigationStack {
                VariableEditorView(
                    title: kind == .source ? "源变量" : "书籍变量",
                    comment: kind == .source
                        ? "源变量可在js中通过source.getVariable()获取"
                        : "书籍变量可在js中通过book.getVariable(\"custom\")获取",
                    value: kind.variableText(book: book, model: model),
                    onSave: { text in
                        kind.save(text, book: book, model: model)
                    }
                )
            }
        }
        .sheet(isPresented: $isCoverPresented) {
            NavigationStack {
                CoverEditorView(
                    coverUrl: book.customCoverUrl ?? "",
                    onSave: { url in
                        var updated = book
                        updated.customCoverUrl = url.isEmpty ? nil : url
                        try? model.environment.store.update(updated)
                        model.reloadBookshelf()
                        message = "已更换封面"
                    }
                )
            }
        }
    }

    /// Puts the book on top of the shelf (the upstream `order = minOrder - 1`).
    private func pin() {
        var updated = book
        let minOrder = (model.books.map(\.order).min() ?? 0) - 1
        updated.order = minOrder
        try? model.environment.store.update(updated)
        model.reloadBookshelf()
        message = "已置顶"
    }

    private func delete() {
        try? model.environment.deleteBook(book)
        model.reloadBookshelf()
        message = "已删除"
    }
}

/// The editor of the book metadata — upstream `BookEditDialog`.
struct BookMetadataEditor: View {

    @State var book: Book
    /// The optional fields are edited as plain strings.
    @State var intro: String = ""
    @State var coverUrl: String = ""
    @State var kind: String = ""
    let onSave: (Book) -> Void

    @Environment(\.dismiss) private var dismiss

    init(book: Book, onSave: @escaping (Book) -> Void) {
        self.book = book
        self.onSave = onSave
        _intro = State(initialValue: book.displayIntro ?? "")
        _coverUrl = State(initialValue: book.displayCoverUrl ?? "")
        _kind = State(initialValue: book.kind ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("信息") {
                    TextField("书名", text: $book.name)
                    TextField("作者", text: $book.author)
                    TextField("分类", text: $kind)
                    TextField("封面", text: $coverUrl)
                }
                Section("简介") {
                    TextEditor(text: $intro)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("编辑书籍")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        var updated = book
                        updated.customIntro = intro.isEmpty ? nil : intro
                        updated.customCoverUrl = coverUrl.isEmpty ? nil : coverUrl
                        updated.kind = kind.isEmpty ? nil : kind
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The pasteboard helper (the upstream copies the book URL to the clipboard).
enum UIPasteboardShim {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    /// The text of the clipboard — upstream `Context.getClipText()`
    /// (`utils/ActivityExtensions.kt`), used by the import of the themes.
    static func string() -> String {
        #if canImport(UIKit)
        return UIPasteboard.general.string ?? ""
        #else
        return ""
        #endif
    }

    /// The text of the clipboard, or nil when it is empty.
    static func paste() -> String? {
        let text = string()
        return text.isEmpty ? nil : text
    }
}

/// Which variable the editor edits — upstream `BookInfoActivity.setSourceVariable`
/// and `setBookVariable`.
enum VariableKind: String, Identifiable {
    case source
    case book

    var id: String { rawValue }

    /// The current value of the variable.
    func variableText(book: Book, model: LegadoAppModel) -> String {
        switch self {
        case .source:
            guard let source = try? model.environment.source(for: book) else { return "" }
            return BookSourceVariables.sourceVariables(source.key) ?? ""
        case .book:
            return book.variable ?? ""
        }
    }

    /// Saves the variable.
    func save(_ text: String, book: Book, model: LegadoAppModel) {
        switch self {
        case .source:
            guard let source = try? model.environment.source(for: book) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let value = try? JSONValue.parse(trimmed),
                  let members = value.objectValue else {
                BookSourceVariables.clearSourceVariables(source.key)
                return
            }
            var variables: [String: String] = [:]
            for (name, member) in members {
                variables[name] = member.textValue
            }
            BookSourceVariables.setVariables(variables, for: source.key)
        case .book:
            var updated = book
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.variable = trimmed.isEmpty ? nil : trimmed
            try? model.environment.store.update(updated)
            model.reloadBookshelf()
        }
    }
}

/// The variable editor — upstream `ui/book/info/VariableDialog`.
struct VariableEditorView: View {

    @Environment(\.dismiss) private var dismiss

    let title: String
    let comment: String
    @State var value: String
    let onSave: (String) -> Void

    init(title: String, comment: String, value: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.comment = comment
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(comment)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            TextEditor(text: $value)
                .font(.system(size: 13))
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.3))
            Spacer()
        }
        .padding(16)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    onSave(value)
                    dismiss()
                }
            }
        }
    }
}

/// The cover editor — upstream `ChangeCoverDialog`.
struct CoverEditorView: View {

    @Environment(\.dismiss) private var dismiss

    @State var coverUrl: String
    let onSave: (String) -> Void

    init(coverUrl: String, onSave: @escaping (String) -> Void) {
        self._coverUrl = State(initialValue: coverUrl)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("封面地址", text: $coverUrl)
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
        .padding(16)
        .navigationTitle("更换封面")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    onSave(coverUrl)
                    dismiss()
                }
            }
        }
    }
}
