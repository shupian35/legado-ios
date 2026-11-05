//
//  ReaderImageViews.swift
//  LegadoUI
//
//  The preview of an inline image and the menu that the long press opens.
//
//  Upstream references:
//  - `app/src/main/java/io/legado/app/ui/book/read/ReadBookActivity.kt:1387`
//    (`onImageLongPress` → 显示 / 刷新 / 保存 / 菜单 / 选择文件夹)
//  - `app/src/main/java/io/legado/app/ui/book/read/dialog/PhotoDialog.kt`
//    (the preview)
//  - `app/src/main/java/io/legado/app/constant/AppConst.kt:46` (`imagePathKey`)
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The preview of an image — upstream `PhotoDialog(src)`.
///
/// The upstream shows the image full screen and lets the reader zoom and
/// pan it; the port shows the image scaled to fit with a close button.
public struct ImagePreviewView: View {

    /// The controller of the reader — it owns the cache of the images.
    @ObservedObject var controller: ReaderController
    /// The source of the image.
    let src: String
    /// Whether the image is zoomed.
    @State private var isZoomed = false

    @Environment(\.dismiss) private var dismiss

    public init(controller: ReaderController, src: String) {
        self.controller = controller
        self.src = src
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            imageView
                .padding()
            VStack {
                HStack {
                    Spacer()
                    Button("关闭") { dismiss() }
                        .padding()
                }
                Spacer()
            }
        }
    }

    /// The image — the cached bytes first, the remote image otherwise.
    @ViewBuilder
    private var imageView: some View {
        let absolute = NetworkUtils.absoluteURL(base: controller.book.tocUrl, src)
        if let data = controller.environment.cacheStorage?.image(book: controller.book, src: absolute) {
            cachedImage(data)
        } else if let url = URL(string: absolute), url.scheme != nil {
            AsyncImage(url: url) { phase in
                if case .success(let loaded) = phase {
                    return AnyView(
                        loaded.resizable()
                            .aspectRatio(contentMode: .fit)
                    )
                }
                return AnyView(EmptyView())
            }
        } else {
            Text("图片加载失败")
                .foregroundColor(.white)
        }
    }

    /// The cached bytes as a platform image — the `UIImage` on iOS, the
    /// `NSImage` on macOS.
    @ViewBuilder
    private func cachedImage(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let platformImage = UIImage(data: data) {
            Image(uiImage: platformImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Text("图片加载失败")
                .foregroundColor(.white)
        }
        #elseif canImport(AppKit)
        if let platformImage = NSImage(data: data) {
            Image(nsImage: platformImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Text("图片加载失败")
                .foregroundColor(.white)
        }
        #else
        Text("图片加载失败")
            .foregroundColor(.white)
        #endif
    }
}

/// The menu of an image — upstream `ReadBookActivity.onImageLongPress`.
///
/// The five entries of the upstream: 显示 (show), 刷新 (refresh),
/// 保存 (save), 菜单 (the reader's menu) and 选择文件夹 (the folder of the
/// saved images).
public struct ImageMenuView: View {

    @ObservedObject var controller: ReaderController
    /// The source of the image.
    let src: String
    /// The message of the last action.
    @State private var message: String?
    /// Whether the folder picker is open.
    @State private var isSelectingFolder = false
    /// The file that was saved (it is shared with the user).
    @State private var savedFile: URL?
    /// Whether the share sheet is open.
    @State private var isSharing = false

    @Environment(\.dismiss) private var dismiss

    public init(controller: ReaderController, src: String) {
        self.controller = controller
        self.src = src
    }

    public var body: some View {
        NavigationStack {
            List {
                Button {
                    dismiss()
                    controller.previewImage(src: src)
                } label: {
                    Label("显示", systemImage: "eye")
                }
                Button {
                    Task {
                        await controller.refreshImage(src: src)
                        dismiss()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                Button {
                    dismiss()
                    controller.isMenuPresented = true
                } label: {
                    Label("菜单", systemImage: "list.bullet")
                }
                Button {
                    isSelectingFolder = true
                } label: {
                    Label("选择文件夹", systemImage: "folder")
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("图片")
            .legadoInlineNavigationTitle()
            .fileImporter(
                isPresented: $isSelectingFolder,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    // The upstream keeps the folder in the cache
                    // (`ACache.put(AppConst.imagePathKey, uri)`).
                    try? controller.environment.store.putCache(
                        "imagePath",
                        value: url.path,
                        deadline: 0
                    )
                    message = "图片保存目录：\(url.lastPathComponent)"
                }
            }
            .sheet(isPresented: $isSharing) {
                if let savedFile {
                    ShareSheet(items: [savedFile])
                }
            }
        }
    }

    /// Saves the image — upstream `viewModel.saveImage(src, uri)`.
    ///
    /// The upstream writes the file into the folder that was picked with
    /// 选择文件夹; the port writes it into the documents folder when no folder
    /// was picked and shares it with the user.
    private func save() {
        let absolute = NetworkUtils.absoluteURL(base: controller.book.tocUrl, src)
        guard let data = controller.environment.cacheStorage?.image(book: controller.book, src: absolute) else {
            message = "图片尚未缓存，请先刷新"
            return
        }
        let folder = (try? controller.environment.store.cache("imagePath", now: Int64(Date().timeIntervalSince1970 * 1000)))
            .flatMap { $0 }
        let name = URL(string: absolute)?.lastPathComponent ?? "image.jpg"
        let target: URL
        if let folder, !folder.isEmpty {
            target = URL(fileURLWithPath: folder).appendingPathComponent(name)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            target = documents.appendingPathComponent("images").appendingPathComponent(name)
        }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target)
            savedFile = target
            isSharing = true
            message = "已保存：\(target.lastPathComponent)"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }
}
