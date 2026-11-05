//
//  ReaderStyleArchiveView.swift
//  LegadoUI
//
//  The import and the export of the reader style — upstream
//  `BgTextConfigDialog` (the entries 导入配置 / 导出配置 of the menu of the
//  background and the text of the reader).
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/config/BgTextConfigDialog.kt
//  app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt
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

/// The import and the export of the reader style — upstream
/// `BgTextConfigDialog`.
public struct ReaderStyleArchiveView: View {

    @ObservedObject var controller: ReaderController

    /// Whether the file picker is shown — upstream `importConfig`.
    @State private var isImporting = false
    /// Whether the share sheet is shown — upstream `exportConfig`.
    @State private var isSharing = false
    /// The file that was exported.
    @State private var exportedURL: URL?
    /// The message of the last action.
    @State private var message = ""

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        Form {
            Section("导入") {
                Button("导入阅读配置") {
                    isImporting = true
                }
                Text("从 readConfig.zip 导入排版设置、字体和背景")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Section("导出") {
                Button("导出阅读配置") {
                    exportArchive()
                }
                Text("把当前的排版设置导出为 readConfig.zip")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if !message.isEmpty {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                }
            }
        }
        .navigationTitle("阅读配置")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip]
        ) { result in
            switch result {
            case .success(let url):
                importArchive(url)
            case .failure(let error):
                message = "导入失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isSharing) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - The actions

    /// Exports the style — upstream `BgTextConfigDialog.exportConfig`.
    ///
    /// The upstream writes the layout of the share into the archive when the
    /// shared layout is on (`BgTextConfigDialog.kt:278`:
    /// `ReadBookConfig.getExportConfig()`).
    private func exportArchive() {
        let config = controller.exportConfig
        var font: ReaderConfigArchive.File?
        if let path = controller.environment.settings.string(.fontFolder),
           let data = FileManager.default.contents(atPath: path) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            font = ReaderConfigArchive.File(name: name, data: data)
        }
        do {
            let data = try ReaderConfigArchive.archive(config: config, font: font)
            let url = exportURL()
            try data.write(to: url)
            exportedURL = url
            isSharing = true
            message = "已导出：\(url.lastPathComponent)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    /// Imports the style — upstream `ReadBookConfig.import(byteArray)`.
    private func importArchive(_ url: URL) {
        do {
            let payload = try withSecurityScope(url) {
                let data = try Data(contentsOf: url)
                return try ReaderConfigArchive.read(data)
            }
            var fontMessage = ""
            if let font = payload.font {
                let destination = fontDirectory()
                    .appendingPathComponent(font.name)
                try? FileManager.default.createDirectory(
                    at: fontDirectory(),
                    withIntermediateDirectories: true
                )
                try font.data.write(to: destination)
                controller.environment.settings.set(destination.path, for: .fontFolder)
                fontMessage = "，字体：\(font.name)"
            }
            let imported = payload.config
            Task {
                await controller.updateReaderStyle { $0 = imported }
                message = "导入成功\(fontMessage)"
            }
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    /// Runs `body` with the security scoped resource of a picked file — the
    /// API only exists on the Apple platforms.
    private func withSecurityScope<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        #if os(iOS) || os(macOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        return try body()
    }

    /// Where the exported archive is written.
    private func exportURL() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(ReaderConfigArchive.archiveFileName)
    }

    /// Where the imported font is stored — upstream `<externalFiles>/font`.
    private func fontDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("font", isDirectory: true)
    }
}
