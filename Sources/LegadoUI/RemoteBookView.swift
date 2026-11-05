//
//  RemoteBookView.swift
//  LegadoUI
//
//  The remote books — the WebDAV browser of the upstream
//  `ui/book/import/remote/RemoteBookActivity.kt`.
//
//  The user browses the folders of the server, picks the books and imports
//  them into the library.
//
//  The upstream menu (`R.menu.book_remote`) also holds the server
//  configuration, the log and the help — all three are ported here.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The remote book browser.
public struct RemoteBookView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var books: [RemoteBook] = []
    @State private var path: [String] = []
    @State private var selected: Set<String> = []
    @State private var sort: RemoteBookSort = .modification
    @State private var ascending = false
    @State private var isLoading = false
    @State private var status: String?
    @State private var webDavUrl: String = ""
    @State private var webDavAccount: String = ""
    @State private var webDavPassword: String = ""
    /// The search text — upstream `onSearchTextChange`.
    @State private var searchText: String = ""
    /// The server configuration — upstream `menu_server_config`.
    @State private var isServersPresented = false
    /// The log — upstream `menu_log`.
    @State private var isLogPresented = false
    /// The help — upstream `menu_help` (the `webDavBookHelp` document).
    @State private var isHelpPresented = false
    /// The alert "是否重新加入书架？" — upstream `addToBookShelfAgain`.
    @State private var isReAddPresented = false
    @State private var reAddBook: RemoteBook?
    /// The alert "压缩包没有找到" — upstream `showRemoteBookDownloadAlert`.
    @State private var isDownloadArchivePresented = false
    @State private var archiveBook: RemoteBook?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            // Upstream `searchView` — the list is filtered by the file name.
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button("清除") {
                        searchText = ""
                    }
                    .font(.system(size: 12))
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            if isLoading {
                ProgressView("加载中")
                    .padding()
            } else if visibleBooks.isEmpty {
                EmptyState(text: "没有远程书籍")
            } else {
                List(visibleBooks, id: \.path) { book in
                    row(book)
                }
                .listStyle(PlainListStyle())
            }
            if !selected.isEmpty {
                Button("导入选中的 \(selected.count) 本书") {
                    importSelected()
                }
                .padding(8)
            }
        }
        .navigationTitle("远程书籍")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新") {
                    load()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("按名称排序") {
                        sort = .name
                        load()
                    }
                    Button("按修改时间排序") {
                        sort = .modification
                        load()
                    }
                    Button(ascending ? "降序" : "升序") {
                        ascending.toggle()
                        load()
                    }
                } label: {
                    Text("排序")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_server_config` — the `ServersDialog`.
                Button("服务器配置") {
                    isServersPresented = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_log` — the `AppLogDialog`.
                Button("日志") {
                    isLogPresented = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_help` — the `webDavBookHelp` document.
                Button("帮助") {
                    isHelpPresented = true
                }
            }
        }
        .sheet(isPresented: $isServersPresented) {
            NavigationStack {
                ServersView(model: model)
            }
        }
        .sheet(isPresented: $isLogPresented) {
            NavigationStack {
                AppLogView()
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            NavigationStack {
                WebDavBookHelpView()
            }
        }
        .alert("是否重新加入书架？", isPresented: $isReAddPresented) {
            Button("确定") {
                if let reAddBook {
                    importBook(reAddBook)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重新加入书架会再次导入这本书")
        }
        .alert("压缩包没有找到", isPresented: $isDownloadArchivePresented) {
            Button("确定") {
                if let archiveBook {
                    downloadArchive(archiveBook)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("是否下载这本书")
        }
        .onAppear {
            webDavUrl = model.environment.settings.webDavUrl ?? ""
            webDavAccount = model.environment.settings.webDavAccount ?? ""
            webDavPassword = model.environment.settings.webDavPassword ?? ""
            model.reloadWebDavServers()
            load()
        }
    }

    // MARK: - The parts

    /// The books that match the search — upstream
    /// `RemoteBookViewModel.updateCallBackFlow` → `it.filename.contains(key)`.
    private var visibleBooks: [RemoteBook] {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return books }
        return books.filter { $0.filename.contains(key) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("返回上级") {
                    if !path.isEmpty {
                        path.removeLast()
                        load()
                    }
                }
                .disabled(path.isEmpty)
                Text("/" + path.joined(separator: "/"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if let status {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            if webDavUrl.isEmpty || webDavAccount.isEmpty || webDavPassword.isEmpty {
                Text("请先在「备份与恢复」中填写 WebDAV 的地址、账号和密码")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(_ book: RemoteBook) -> some View {
        HStack(spacing: 8) {
            if book.isDir {
                Button {
                    path.append(book.filename)
                    load()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text(book.filename)
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button {
                    // Upstream `RemoteBookAdapter` — a book that is already in
                    // the library is opened, every other book is selected.
                    if book.isOnBookShelf {
                        startRead(book)
                    } else {
                        toggle(book)
                    }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(book.path) ? "checkmark.square" : "square")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.filename)
                            Text(sizeText(book.size))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .contextMenu {
                    // Upstream `RemoteBookAdapter.setOnLongClickListener` —
                    // the long press re-imports a book that is already in the
                    // library.
                    Button("开始阅读") {
                        startRead(book)
                    }
                    Button("重新加入书架") {
                        reAddBook = book
                        isReAddPresented = true
                    }
                }
            }
        }
    }

    private func sizeText(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - The actions

    private func toggle(_ book: RemoteBook) {
        if selected.contains(book.path) {
            selected.remove(book.path)
        } else {
            selected.insert(book.path)
        }
    }

    private func importer() -> RemoteBookImporter? {
        model.remoteBookImporter()
    }

    private func load() {
        guard let importer = importer() else {
            books = []
            return
        }
        isLoading = true
        status = nil
        Task {
            do {
                let listed = try await importer.list(subPath: path.isEmpty ? nil : path.joined(separator: "/"))
                books = model.markRemoteBooksOnShelf(listed)
                books = RemoteBookImporter.sorted(books, by: sort, ascending: ascending)
                selected = selected.filter { path in books.contains { $0.path == path } }
            } catch {
                status = "加载失败：\(error.localizedDescription)"
                books = []
            }
            isLoading = false
        }
    }

    private func importSelected() {
        guard let importer = importer() else { return }
        let chosen = books.filter { selected.contains($0.path) }
        isLoading = true
        Task {
            let count = await model.importRemoteBooks(chosen, importer: importer)
            selected.removeAll()
            status = "已导入 \(count) 本书"
            isLoading = false
            load()
        }
    }

    /// Starts a remote book — upstream `RemoteBookActivity.startRead`.
    ///
    /// A book that is already in the library is opened, an archive that is in
    /// the local storage is unpacked, and an archive that is missing is
    /// downloaded after the user confirms it.
    private func startRead(_ book: RemoteBook) {
        switch model.remoteBookAction(for: book) {
        case .openBook(let bookUrl):
            guard let local = try? model.environment.store.book(url: bookUrl) else { return }
            Task { await model.openReader(for: local) }
        case .openArchive(let fileName):
            guard let imported = model.openLocalArchive(named: fileName) else { return }
            Task { await model.openReader(for: imported) }
        case .downloadArchive:
            archiveBook = book
            isDownloadArchivePresented = true
        case .nothing:
            break
        }
    }

    /// Downloads an archive and imports the books inside it — the OK button of
    /// the "压缩包没有找到" alert.
    private func downloadArchive(_ book: RemoteBook) {
        guard let importer = importer() else { return }
        isLoading = true
        Task {
            let count = await model.downloadRemoteArchive(book, importer: importer)
            status = "已导入 \(count) 本书"
            isLoading = false
            load()
        }
    }

    /// Imports a book again — the OK button of the "是否重新加入书架？" alert.
    private func importBook(_ book: RemoteBook) {
        guard let importer = importer() else { return }
        isLoading = true
        Task {
            let count = await model.importRemoteBooks([book], importer: importer)
            status = "已导入 \(count) 本书"
            isLoading = false
            load()
        }
    }
}

/// The help of the remote-book browser — upstream `menu_help` (the
/// `webDavBookHelp` document).
public struct WebDavBookHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(AppHelpDocuments.webDavBookHelp)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("帮助")
    }
}
