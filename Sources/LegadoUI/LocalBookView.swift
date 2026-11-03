//
//  LocalBookView.swift
//  LegadoUI
//
//  The local book manager — upstream `ui/book/local/*` and the bookshelf's
//  "导入本地书" action.
//
//  The files are imported with `LocalBookImporter` (the copy into the app
//  storage, the table of contents and the chapters).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The local book list and the import action.
public struct LocalBookView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isImporterPresented = false
    @State private var isFolderImporterPresented = false
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                Button("导入本地书") {
                    isImporterPresented = true
                }
                Button("扫描文件夹") {
                    isFolderImporterPresented = true
                }
                NavigationLink {
                    RemoteBookView(model: model)
                } label: {
                    Text("远程书籍（WebDAV）")
                }
                if let message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Section("已导入") {
                if model.localBooks.isEmpty {
                    Text("还没有本地书")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.localBooks, id: \.bookUrl) { book in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(book.name)
                                Text("\(book.author) · \(book.totalChapterNum) 章")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("删除") {
                                model.deleteLocalBook(book)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
            }
        }
        .navigationTitle("本地书")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: LocalBookView.contentTypes,
            onCompletion: { result in
                switch result {
                case let .success(url):
                    model.importLocalBook(from: url)
                case let .failure(error):
                    message = error.localizedDescription
                }
            }
        )
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            onCompletion: { result in
                switch result {
                case let .success(url):
                    scanFolder(url)
                case let .failure(error):
                    message = error.localizedDescription
                }
            }
        )
        .onAppear {
            model.reloadLocalBooks()
        }
    }

    /// Scans a folder and imports every book inside it — upstream
    /// `ImportBookViewModel.scanDoc`.
    private func scanFolder(_ url: URL) {
        let result = LocalBookScanner.scan(directory: url)
        let books = LocalBookScanner.supportedBooks(of: result)
        guard !books.isEmpty else {
            message = "没有找到可导入的书"
            return
        }
        for book in books {
            model.importLocalBook(from: book)
        }
        message = "已导入 \(books.count) 本书"
    }

    /// The accepted file types — upstream `AppPattern` supports
    /// `txt|epub|umd|pdf|mobi|azw3|azw`.
    public static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in ["txt", "epub", "umd", "pdf"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
