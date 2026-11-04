//
//  AppLogView.swift
//  LegadoUI
//
//  The app log screen — upstream
//  `app/src/main/java/io/legado/app/ui/about/AppLogDialog.kt`
//  (the list of the in-memory entries, the 清空 action and the stack trace
//  of an entry with an error).
//
//  The reader's help — upstream
//  `app/src/main/assets/web/help/md/readMenuHelp.md`.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The app log — upstream `AppLogDialog`.
public struct AppLogView: View {

    @State private var entries: [AppLog.Entry] = AppLog.shared.logs
    @State private var selectedTrace: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("清空") {
                    AppLog.shared.clear()
                    entries = AppLog.shared.logs
                }
            }
            if entries.isEmpty {
                Text("没有日志")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                List(entries) { entry in
                    Button {
                        if let trace = entry.errorDescription {
                            selectedTrace = trace
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLog.formatTime(entry.time))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(entry.message)
                                .font(.system(size: 13))
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            entries = AppLog.shared.logs
        }
        .alert("Log", isPresented: Binding(
            get: { selectedTrace != nil },
            set: { if !$0 { selectedTrace = nil } }
        )) {
            Button("好") { selectedTrace = nil }
        } message: {
            Text(selectedTrace ?? "")
        }
    }
}

/// The reader's help — upstream `showHelp("readMenuHelp")`.
public struct ReaderHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(ReaderHelp.text)
                .font(.system(size: 13))
                .padding()
        }
        .navigationTitle("阅读界面帮助")
    }
}

/// The reader's help text — upstream `readMenuHelp.md`.
public enum ReaderHelp {

    public static let text = """
    阅读界面帮助文档

    阅读界面主菜单
    * 顶部操作
      * 章节名称:点击可编辑书源
      * 章节url:点击可打开浏览器浏览
      * 菜单:不同类型的书籍显示的菜单不同
    * 中间左侧-亮度调节
      * 亮度调节的顶端有跟随系统亮度的开关,打开后亮度跟随系统,关闭后才可以调节亮度条
    * 底部操作
      * 4个圆形按钮依次为 全文搜索✧自动翻页✧替换净化✧切换夜间模式
      * 上一章✧下一章中间的进度条为页数进度,要快速跳转章节点击目录按钮进入目录快速跳转
      * 目录->目录和书签界面
      * 朗读->单击开始朗读,长按进入朗读设置界面
      * 界面->所有排版设置都在里面
      * 设置->其它一些设置,找不到的设置去这里看看,可滚动

    全文搜索
    搜索本地缓存或者本地文件，不能搜索在线内容
    书籍字数、净化规则数量、简繁转化、文章分段都会影响到搜索速度，请酌情启用

    朗读设置界面
    * 后台->进入后台朗读,可以做一些其它事
    * 设置->朗读引擎设置,可以切换本地TTS和在线朗读,在线朗读可自定义

    排版设置界面
    * 白天模式和夜间模式背景不同布局相同
    * 共用布局->启用共用布局时所有背景使用同一布局,关闭共用布局则每个背景单独布局
    * 长按背景可进入文字颜色和背景设置界面

    其它设置界面
    * 屏幕方向
    * 屏幕超时
    * 隐藏状态栏
    * 扩展到刘海
    * 隐藏导航栏
    * 文字两端对齐
    * 文字底部对齐
    * 音量键翻页
    * 点击翻页
    * 朗读时音量键翻页
    * 自动换源->书源被删除时自动切换到其它书源
    * 长按选择文本
    * 显示亮度调节控件
    * 点击区域设置
    * 自定义翻页按键
    """
}
