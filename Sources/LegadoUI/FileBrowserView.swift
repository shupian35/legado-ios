//
//  FileBrowserView.swift
//  LegadoUI
//
//  The file manager — upstream `ui/file/FileManageActivity`.
//
//  The upstream browses the app's own files folder, lists the folders before
//  the files, offers a search and deletes a file through the long press menu.
//
//  See `FileBrowser.swift` in LegadoCore for the logic.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The file manager — upstream `FileManageActivity`.
public struct FileBrowserView: View {

    /// The root of the browser — upstream
    /// `context.getExternalFilesDir(null)?.parentFile` (the app's own
    /// documents folder on iOS).
    private let root: URL

    /// The folders of the current path — upstream `viewModel.subDocs`.
    @State private var path: [URL] = []

    /// The entries of the current folder.
    @State private var entries: [BrowserEntry] = []

    /// The search — upstream `searchView`.
    @State private var query = ""

    /// The entry whose deletion is confirmed.
    @State private var pendingDelete: BrowserEntry?

    /// The message of the last action.
    @State private var message: String?

    /// The shared file.
    @State private var shareItems: [Any] = []

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    public var body: some View {
        List {
            Section {
                // The path bar — upstream `PathAdapter`: the "root" header
                // plus the folders of the current path.
                HStack(spacing: 8) {
                    Button("root") {
                        path = []
                        reload()
                    }
                    .font(.system(size: 13))
                    ForEach(Array(path.enumerated()), id: \.offset) { index, folder in
                        Button(folder.lastPathComponent) {
                            path = Array(path.prefix(index + 1))
                            reload()
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            Section {
                if entries.isEmpty {
                    Text("空文件夹")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                ForEach(visibleEntries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text(entry.name)
                                .font(.system(size: 14))
                            if !entry.isDirectory {
                                Text(entry.size.formattedSize)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        open(entry)
                    }
                    .contextMenu {
                        Button("分享", role: .destructive) {
                            shareItems = [entry.url]
                        }
                        Button("删除", role: .destructive) {
                            pendingDelete = entry
                        }
                    }
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
        .navigationTitle("文件管理")
        .searchable(text: $query, prompt: "搜索 • 文件管理")
        .onAppear { reload() }
        .onChange(of: query) { _ in }
        .confirmationDialog(
            pendingDelete.map { "确定删除 \($0.name)？" } ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDelete {
                    message = FileBrowser.delete(entry) ? "已删除 \(entry.name)" : "删除失败"
                }
                pendingDelete = nil
                reload()
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: Binding(
            get: { !shareItems.isEmpty },
            set: { if !$0 { shareItems = [] } }
        )) {
            ShareSheet(items: shareItems)
        }
    }

    /// The entries after the search — upstream `updateFiles`.
    private var visibleEntries: [BrowserEntry] {
        FileBrowser.filtered(entries, query: query)
    }

    /// The current folder.
    private var current: URL {
        path.last ?? root
    }

    /// Opens a folder or a file — upstream `FileAdapter.registerListener`.
    private func open(_ entry: BrowserEntry) {
        if entry.isDirectory {
            path.append(entry.url)
            reload()
        } else {
            shareItems = [entry.url]
        }
    }

    /// Reloads the current folder — upstream `viewModel.upFiles(lastDir)`.
    private func reload() {
        entries = FileBrowser.list(current)
    }
}

extension Int64 {
    /// The size of a file in a readable form.
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: self)
    }
}
