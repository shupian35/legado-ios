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
public struct BookshelfManageView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var books: [Book] = []
    @State private var selection: Set<String> = []
    @State private var message: String?
    @State private var isGroupPickerPresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(books, id: \.bookUrl) { book in
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
                    }
                }
            }
        }
        .navigationTitle("书架管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("全选") {
                    selection = Set(books.map(\.bookUrl))
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("取消") {
                    selection.removeAll()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("删除") {
                    deleteSelected()
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
        }
        .sheet(isPresented: $isGroupPickerPresented) {
            NavigationStack {
                GroupPickerView(model: model) { groupId in
                    moveSelected(to: groupId)
                }
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        books = (try? model.environment.store.allBooks()) ?? []
    }

    private func toggle(_ book: Book) {
        if selection.contains(book.bookUrl) {
            selection.remove(book.bookUrl)
        } else {
            selection.insert(book.bookUrl)
        }
    }

    private var selectedBooks: [Book] {
        books.filter { selection.contains($0.bookUrl) }
    }

    private func deleteSelected() {
        for book in selectedBooks {
            try? model.environment.deleteBook(book)
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

    private func moveSelected(to groupId: Int64) {
        for book in selectedBooks {
            var changed = book
            changed.group = changed.group | groupId
            try? model.environment.store.update(changed)
        }
        reload()
        model.reloadBookshelf()
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
