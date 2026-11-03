//
//  MangaConfigViews.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/manga/config/MangaColorFilterDialog.kt
//  app/src/main/java/io/legado/app/ui/book/manga/config/MangaFooterSettingDialog.kt
//
//  The two configuration dialogs of the manga reader.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The colour filter of the manga reader — upstream `MangaColorFilterDialog`.
public struct MangaColorFilterSheet: View {

    /// The controller of the manga reader.
    @ObservedObject var controller: MangaReaderController

    @State private var config = MangaColorFilter()
    @Environment(\.dismiss) private var dismiss

    public init(controller: MangaReaderController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("颜色滤镜") {
                    slider("红", value: $config.r)
                    slider("绿", value: $config.g)
                    slider("蓝", value: $config.b)
                    slider("透明度", value: $config.a)
                    slider("亮度", value: $config.l)
                }
                Section {
                    Button("重置") {
                        config = MangaColorFilter()
                    }
                    Button("取消") {
                        dismiss()
                    }
                    Button("确定") {
                        MangaSettings.setColorFilter(config, settings: controller.environment.settings)
                        controller.refreshDisplay()
                        dismiss()
                    }
                }
            }
            .navigationTitle("颜色滤镜")
        }
        .onAppear {
            config = MangaSettings.colorFilter(controller.environment.settings)
        }
    }

    /// One of the five sliders — the upstream dialog has the same five.
    private func slider(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...255
            )
        }
    }
}

/// The footer configuration of the manga reader — upstream
/// `MangaFooterSettingDialog`.
public struct MangaFooterConfigSheet: View {

    /// The controller of the manga reader.
    @ObservedObject var controller: MangaReaderController

    @State private var config = MangaFooterConfig()
    @Environment(\.dismiss) private var dismiss

    public init(controller: MangaReaderController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("章节") {
                    Toggle("隐藏标题", isOn: $config.hideChapterLabel)
                    Toggle("隐藏章节名", isOn: $config.hideChapterName)
                    Toggle("隐藏章节", isOn: $config.hideChapter)
                }
                Section("页码") {
                    Toggle("隐藏页码标题", isOn: $config.hidePageNumberLabel)
                    Toggle("隐藏页码", isOn: $config.hidePageNumber)
                }
                Section("进度") {
                    Toggle("隐藏进度标题", isOn: $config.hideProgressRatioLabel)
                    Toggle("隐藏进度", isOn: $config.hideProgressRatio)
                }
                Section("页脚") {
                    Toggle("隐藏页脚", isOn: $config.hideFooter)
                    Picker("对齐", selection: $config.footerOrientation) {
                        Text("靠左").tag(0)
                        Text("居中").tag(1)
                        Text("靠右").tag(2)
                    }
                }
                Section {
                    Button("取消") {
                        dismiss()
                    }
                    Button("确定") {
                        MangaSettings.setFooterConfig(config, settings: controller.environment.settings)
                        controller.refreshDisplay()
                        dismiss()
                    }
                }
            }
            .navigationTitle("页脚设置")
        }
        .onAppear {
            config = MangaSettings.footerConfig(controller.environment.settings)
        }
    }
}
