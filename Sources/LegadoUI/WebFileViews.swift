//
//  WebFileViews.swift
//  LegadoUI
//
//  The files of a book that comes from a download service — upstream
//  `BookInfoActivity.showWebFileDownloadAlert`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/info/BookInfoActivity.kt:626-665
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The picker of the downloadable files of a book — upstream
/// `BookInfoActivity.showWebFileDownloadAlert` (the dialog
/// "下载并导入文件").
public struct WebFilePickerView: View {

    /// The files — upstream `BookInfoViewModel.webFiles`.
    private let files: [WebFile]

    /// The action of a picked file — upstream the `selector` callback.
    private let onPick: (WebFile) -> Void

    public init(files: [WebFile], onPick: @escaping (WebFile) -> Void) {
        self.files = files
        self.onPick = onPick
    }

    public var body: some View {
        List {
            Section {
                ForEach(files) { file in
                    Button {
                        onPick(file)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.body)
                                Text(file.url)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if !file.isSupported, !file.isSupportDecompress {
                                // Upstream `R.string.file_not_supported`.
                                Text("不支持的文件")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationTitle("下载并导入文件")
    }
}
