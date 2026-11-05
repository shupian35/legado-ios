//
//  BookshelfToolsViews.swift
//  LegadoUI
//
//  The bookshelf tools — upstream `ui/main/bookshelf/`.
//
//  * `GroupManageView` — the group manager (upstream
//    `ui/main/bookshelf/dialog/GroupManageDialog.kt`).
//  * `AddBookByUrlView` — add a book by its address (upstream
//    `BookshelfViewModel.addBookByUrl`).
//  * `ExportBookshelfView` — the shelf as `books.json` (upstream
//    `BookshelfViewModel.exportBookshelf`).
//  * `ImportBookshelfView` — read a shelf back (upstream
//    `BookshelfViewModel.importBookshelf`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The group manager

/// The group manager — upstream `GroupManageDialog`.
///
/// The upstream dialog adds a group, renames it, deletes it, hides it and
/// reorders it; the port reproduces all of that.
public struct GroupManageView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isAdding = false
    @State private var newGroupName = ""
    @State private var editingGroup: BookGroup?
    @State private var editName = ""
    /// The group whose cover is being picked — upstream `GroupEditDialog`'s
    /// `selectImage` launcher.
    @State private var coverGroup: BookGroup?
    @State private var isPickingCover = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("分组") {
                ForEach(model.userGroups, id: \.groupId) { group in
                    row(group)
                }
                .onMove { source, destination in
                    model.moveGroups(from: source, to: destination)
                }
            }
        }
        .navigationTitle("分组管理")
        .legadoInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    newGroupName = ""
                    isAdding = true
                }
            }
        }
        .fileImporter(isPresented: $isPickingCover, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                pickCover(url)
            }
            coverGroup = nil
        }
        .alert("添加分组", isPresented: $isAdding) {
            TextField("分组名称", text: $newGroupName)
            Button("取消", role: .cancel) {}
            Button("确定") {
                model.addGroup(name: newGroupName)
            }
        } message: {
            Text("分组名称不能为空")
        }
        .alert("修改分组", isPresented: Binding(get: { editingGroup != nil }, set: { if !$0 { editingGroup = nil } })) {
            TextField("分组名称", text: $editName)
            Button("取消", role: .cancel) {
                editingGroup = nil
            }
            Button("确定") {
                if let group = editingGroup {
                    model.renameGroup(group, name: editName)
                }
                editingGroup = nil
            }
        } message: {
            Text("分组名称不能为空")
        }
    }

    /// One row of the group list.
    private func row(_ group: BookGroup) -> some View {
        HStack(spacing: 10) {
            // Upstream `GroupEditDialog` — the group cover.
            if let cover = group.cover, !cover.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.groupName)
                    .font(.system(size: 15))
                Text("ID \(group.groupId)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            // Upstream `GroupManageDialog` — the per group switches.
            Toggle("显示", isOn: Binding(
                get: { group.show },
                set: { model.setGroup(group, show: $0) }
            ))
            .labelsHidden()
            Toggle("刷新", isOn: Binding(
                get: { group.enableRefresh },
                set: { model.setGroup(group, enableRefresh: $0) }
            ))
            .labelsHidden()
            Menu {
                Button("重命名") {
                    editName = group.groupName
                    editingGroup = group
                }
                // Upstream `GroupEditDialog` — the `ivCover` image picker.
                Button("设置封面") {
                    coverGroup = group
                    isPickingCover = true
                }
                if let cover = group.cover, !cover.isEmpty {
                    Button("清除封面", role: .destructive) {
                        model.setGroupCover(group, cover: nil)
                    }
                }
                // Upstream `GroupEditDialog` — the `spSort` spinner with the
                // `book_sort` array (the default plus the six sorts).
                Menu("排序") {
                    Button("默认") {
                        model.setGroupSort(group, sort: -1)
                    }
                    ForEach(BookshelfSort.allCases, id: \.rawValue) { sort in
                        Button(sort.name) {
                            model.setGroupSort(group, sort: sort.rawValue)
                        }
                    }
                }
                Button("删除", role: .destructive) {
                    model.deleteGroup(group)
                }
            } label: {
                Text("更多")
                    .font(.system(size: 13))
            }
        }
    }

    /// Copies the picked image into the app's own directory and stores its
    /// path in the group — upstream `GroupEditDialog`'s `selectImage`.
    private func pickCover(_ url: URL) {
        guard let group = coverGroup else { return }
        do {
            let path = try LocalFileStore.importFile(from: url, into: "covers")
            model.setGroupCover(group, cover: path)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add a book by its address

/// Adds books by their address — upstream `BookshelfViewModel.addBookByUrl`.
///
/// The address is matched against the sources that have a `bookUrlPattern`
/// (upstream `BookSourceDao.hasBookUrlPattern`).
public struct AddBookByUrlView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var urls = ""
    @State private var isWorking = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                TextField("书籍地址，一行一个", text: $urls, axis: .vertical)
                    .lineLimit(4)
                    .autocorrectionDisabled()
                    .legadoNoAutocapitalization()
            }
            if let message {
                Section {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("添加网址")
        .legadoInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    add()
                }
                .disabled(isWorking)
            }
        }
    }

    /// Adds the books of the text field.
    private func add() {
        isWorking = true
        Task {
            let result = await model.addBooksByUrl(urls)
            isWorking = false
            message = result
            if result.hasPrefix("成功") {
                dismiss()
            }
        }
    }
}

// MARK: - Export the shelf

/// Exports the shelf as `books.json` — upstream
/// `BookshelfViewModel.exportBookshelf`.
///
/// The document is a JSON array of `{name, author, intro}` objects.
public struct ExportBookshelfView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var text = ""
    @State private var didCopy = false
    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                TextField("文件名", text: .constant("books.json"))
                    .disabled(true)
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(12)
            }
            Section {
                Button("复制到剪贴板") {
                    UIPasteboardShim.copy(text)
                    didCopy = true
                }
                if let url = model.environment.cacheStorage?.layout.root
                    .appendingPathComponent("books.json") {
                    Button("保存到 \(url.lastPathComponent)") {
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                        didCopy = true
                    }
                }
            }
            if didCopy {
                Section {
                    Text("已保存")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("导出书架")
        .legadoInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            text = BookshelfExport.json(books: model.visibleBooks)
        }
    }
}

// MARK: - Import the shelf

/// Reads a shelf back — upstream `BookshelfViewModel.importBookshelf`.
///
/// The text is either an absolute address (the document is fetched) or a JSON
/// array of `{name, author, intro}` objects. The books that are already on
/// the shelf are skipped.
public struct ImportBookshelfView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var text = ""
    @State private var isWorking = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                TextField("书架地址或 JSON", text: $text, axis: .vertical)
                    .lineLimit(6)
                    .autocorrectionDisabled()
                    .legadoNoAutocapitalization()
            }
            if let message {
                Section {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("导入书架")
        .legadoInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("导入") {
                    importShelf()
                }
                .disabled(isWorking)
            }
        }
    }

    /// Imports the shelf of the text field.
    private func importShelf() {
        isWorking = true
        Task {
            let result = await model.importBookshelf(text)
            isWorking = false
            message = result
            if result.hasPrefix("成功") {
                dismiss()
            }
        }
    }
}

// MARK: - The shelf document

/// The `books.json` document — upstream `BookshelfViewModel.exportBookshelf`.
///
/// The format is a JSON array of `{name, author, intro}` objects; the intro is
/// the display intro (`Book.getDisplayIntro()`), i.e. the custom intro when
/// there is one.
public enum BookshelfExport {

    /// The JSON document of the books.
    public static func json(books: [Book]) -> String {
        let rows: [JSONValue] = books.map { book in
            JSONValue.object([
                "name": .string(book.name),
                "author": .string(book.author),
                "intro": .string(book.displayIntro ?? book.intro ?? "")
            ])
        }
        return JSONValue.array(rows).jsonString
    }

    /// The books of a `books.json` document — upstream
    /// `BookshelfViewModel.importBookshelfByJson`.
    ///
    /// The rows without a name are skipped, exactly like the upstream.
    public static func parse(_ text: String) -> [(name: String, author: String, intro: String)] {
        guard let value = try? JSONValue.parse(text),
              let rows = value.arrayValue else { return [] }
        var result: [(name: String, author: String, intro: String)] = []
        for row in rows {
            guard let object = row.objectValue else { continue }
            let name = object["name"]?.stringValue ?? ""
            guard !name.isEmpty else { continue }
            result.append((
                name: name,
                author: object["author"]?.stringValue ?? "",
                intro: object["intro"]?.stringValue ?? ""
            ))
        }
        return result
    }
}
