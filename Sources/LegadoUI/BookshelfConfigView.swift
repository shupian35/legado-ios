//
//  BookshelfConfigView.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/main/bookshelf/BaseBookshelfFragment.kt:165-239
//  (`configBookshelf`) and
//  app/src/main/res/layout/dialog_bookshelf_config.xml.
//
//  The upstream dialog configures the bookshelf: the style of the groups (the
//  tags or the folders), the four display switches (the unread mark, the time
//  of the last update, the number of the books that wait for an update and the
//  fast scroll bar), the layout (the list or a grid of three to six columns)
//  and the sort order.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The bookshelf configuration — upstream `BaseBookshelfFragment.configBookshelf`.
public struct BookshelfConfigView: View {

    @ObservedObject var model: LegadoAppModel
    @Environment(\.dismiss) private var dismiss

    /// The style of the groups — upstream `AppConfig.bookGroupStyle`
    /// (0 = the tags, 1 = the folders).
    @State private var groupStyle = 0
    /// Whether the unread mark is shown — upstream `AppConfig.showUnread`.
    @State private var showUnread = true
    /// Whether the time of the last update is shown — upstream
    /// `AppConfig.showLastUpdateTime`.
    @State private var showLastUpdateTime = false
    /// Whether the number of the books that wait for an update is shown —
    /// upstream `AppConfig.showWaitUpCount`.
    @State private var showWaitUpCount = false
    /// Whether the fast scroll bar is shown — upstream
    /// `AppConfig.showBookshelfFastScroller`.
    @State private var showFastScroller = false
    /// The layout — upstream `AppConfig.bookshelfLayout` (0 = the list, 1…4 =
    /// a grid of three to six columns).
    @State private var layout = 0
    /// The sort order — upstream `AppConfig.bookshelfSort`.
    @State private var sort = 0

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("分组样式") {
                Picker("分组样式", selection: $groupStyle) {
                    Text("标签").tag(0)
                    Text("文件夹").tag(1)
                }
            }
            Section("显示") {
                Toggle("显示未读标志", isOn: $showUnread)
                Toggle("显示上次更新时间", isOn: $showLastUpdateTime)
                Toggle("显示待更新数量", isOn: $showWaitUpCount)
                Toggle("显示快速滚动条", isOn: $showFastScroller)
            }
            Section("视图") {
                Picker("视图", selection: $layout) {
                    Text("列表").tag(0)
                    Text("网格三列").tag(1)
                    Text("网格四列").tag(2)
                    Text("网格五列").tag(3)
                    Text("网格六列").tag(4)
                }
            }
            Section("排序") {
                Picker("排序", selection: $sort) {
                    Text("按阅读时间").tag(0)
                    Text("按更新时间").tag(1)
                    Text("按书名").tag(2)
                    Text("手动排序").tag(3)
                    Text("综合排序").tag(4)
                    Text("按作者").tag(5)
                }
            }
        }
        .navigationTitle("书架布局")
        .legadoInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("确定") {
                    apply()
                    dismiss()
                }
            }
        }
        .onAppear {
            load()
        }
    }

    /// Reads the current preferences — upstream the dialog fills itself with
    /// the current values.
    private func load() {
        let settings = model.environment.settings
        groupStyle = settings.int(.bookGroupStyle, default: 0)
        showUnread = settings.bool(.showUnread, default: true)
        showLastUpdateTime = settings.bool(.showLastUpdateTime, default: false)
        showWaitUpCount = settings.bool(.showWaitUpCount, default: false)
        showFastScroller = settings.bool(.showBookshelfFastScroller, default: false)
        layout = settings.bookshelfLayout
        sort = settings.bookshelfSort
    }

    /// Saves the preferences — upstream the OK button writes the values and
    /// refreshes the shelf.
    private func apply() {
        let settings = model.environment.settings
        settings.set(groupStyle, for: .bookGroupStyle)
        settings.set(showUnread, for: .showUnread)
        settings.set(showLastUpdateTime, for: .showLastUpdateTime)
        settings.set(showWaitUpCount, for: .showWaitUpCount)
        settings.set(showFastScroller, for: .showBookshelfFastScroller)
        settings.bookshelfLayout = layout
        settings.bookshelfSort = sort
        model.reloadBookshelf()
    }
}
