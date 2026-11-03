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

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                ProgressView("加载中")
                    .padding()
            } else if books.isEmpty {
                EmptyState(text: "没有远程书籍")
            } else {
                List(books, id: \.path) { book in
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
        }
        .onAppear {
            webDavUrl = model.environment.settings.webDavUrl ?? ""
            webDavAccount = model.environment.settings.webDavAccount ?? ""
            webDavPassword = model.environment.settings.webDavPassword ?? ""
            load()
        }
    }

    // MARK: - The parts

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
                    toggle(book)
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
        guard !webDavUrl.isEmpty, !webDavAccount.isEmpty, !webDavPassword.isEmpty else { return nil }
        let configuration = WebDavConfiguration(
            url: webDavUrl,
            username: webDavAccount,
            password: webDavPassword,
            backupDirectory: "",
            bookProgressDirectory: "bookProgress/",
            booksDirectory: "books/",
            backgroundDirectory: "background/"
        )
        let client = WebDavClient(configuration: configuration, httpClient: model.environment.httpClient)
        return RemoteBookImporter(client: client, rootPath: "books/")
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
                books = RemoteBookImporter.sorted(listed, by: sort, ascending: ascending)
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
}
