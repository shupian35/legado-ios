//
//  AboutDocuments.swift
//  LegadoUI
//
//  The documents of the about screen — upstream `ui/about/AboutFragment.kt`.
//
//  Upstream `AboutFragment.onPreferenceTreeClick` (L56-71) opens:
//  the contributors page (a URL), the update log (`updateLog.md`), the
//  license (`LICENSE.md`), the disclaimer (`disclaimer.md`), the privacy
//  policy (`privacyPolicy.md`), the crash logs and the "save the logs"
//  action (a zip in the backup directory).
//
//  The Markdown files are copied verbatim from the upstream assets into
//  `Sources/LegadoAppUI/Resources` — the XcodeGen project copies that folder
//  into the app bundle.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The documents

/// The documents of the about screen.
public enum AboutDocument: String, CaseIterable, Identifiable, Sendable {

    /// The update log — upstream `updateLog.md`.
    case updateLog
    /// The license — upstream `LICENSE.md`.
    case license
    /// The disclaimer — upstream `disclaimer.md`.
    case disclaimer
    /// The privacy policy — upstream `privacyPolicy.md`.
    case privacyPolicy

    public var id: String { rawValue }

    /// The name of the file in the bundle.
    public var fileName: String {
        switch self {
        case .updateLog: return "updateLog.md"
        case .license: return "LICENSE.md"
        case .disclaimer: return "disclaimer.md"
        case .privacyPolicy: return "privacyPolicy.md"
        }
    }

    /// The title of the document — upstream `res/values/strings.xml`.
    public var title: String {
        switch self {
        case .updateLog: return "更新日志"
        case .license: return "开源许可"
        case .disclaimer: return "免责声明"
        case .privacyPolicy: return "隐私政策"
        }
    }

    /// The inline copy of the document — the upstream's asset.
    ///
    /// The license is too long to inline, so it is only read from the bundle.
    public var inlineText: String {
        switch self {
        case .updateLog: return AboutDocument.updateLogText
        case .license: return ""
        case .disclaimer: return AboutDocument.disclaimerText
        case .privacyPolicy: return AboutDocument.privacyPolicyText
        }
    }

    /// The text of the document — the bundle first, the inline copy second.
    public var text: String {
        if let url = Bundle.main.url(forResource: (rawValue == "license" ? "LICENSE" : rawValue), withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return inlineText
    }

    /// The update log — upstream `assets/updateLog.md`.
    static let updateLogText = """
    # 更新日志

    * 关注公众号 **[开源阅读]** 菜单•软件下载 提前享受新版本。
    * 关注合作公众号 **[小说拾遗]** 获取好看的小说。

    ## **必读**

    【温馨提醒】 *更新前一定要做好备份，以免数据丢失！*

    * 阅读只是一个转码工具，不提供内容，第一次安装app，需要自己手动导入书源，可以从公众号 **[开源阅读]**
      、QQ群、酷安评论里获取由书友制作分享的书源。
    * 正文出现缺字漏字、内容缺失、排版错乱等情况，有可能是净化规则或简繁转换出现问题。
    * 漫画源看书显示乱码，**阅读与其他软件的源并不通用**，请导入阅读的支持的漫画源！

    **2025/03/26**
    * 目前阅读被恶意注册软著，并建立了多个公众号
    * 官方公众号仅有：开源阅读、开源阅读软件，其他公众号与本软件无关

    **2024/10/03**
    * web书架支持加载网络字体、试读非书架书籍后弹窗、自定义后端IP
    * rss收藏添加分组管理
    * 朗读功能添加流式播放音频、来电自动暂停播放功能
    * 其它bug修复

    **2024/02/27**
    * 添加备用URL导出
    * 更新书源制作的帮助文档链接

    **2024/02/20**
    * 更新cronet: 121.0.6167.180
    * 更新 kotlin->1.9.22 ksp->1.0.17
    * 界面绘制优化
    * Bug修复和其他优化

    ----

    * [2023年日志](https://github.com/gedoor/legado/blob/record2023/app/src/main/assets/updateLog.md)
    * [2022年日志](https://github.com/gedoor/legado/blob/record2022/app/src/main/assets/updateLog.md)
    * [2021年日志](https://github.com/gedoor/legado/blob/record2021/app/src/main/assets/updateLog.md)
    """

    /// The disclaimer — upstream `assets/disclaimer.md`.
    static let disclaimerText = """
    # 免责声明（Disclaimer）

    * 阅读是一款解析指定规则并获取内容的工具，为广大网络文学爱好者提供一种方便、快捷舒适的试读体验。
    * 当您搜索一本书的时，阅读会您所使用的规则将该书的书名以关键词的形式提交到各个第三方网络文学网站。
    各第三方网站返回的内容与阅读无关，阅读对其概不负责，亦不承担任何法律责任。
    任何通过使用阅读而链接到的第三方网页均系他人制作或提供，您可能从第三方网页上获得其他服务，阅读对其合法性概不负责，亦不承担任何法律责任。
    第三方搜索引擎结果根据您提交的书名自动搜索获得并提供试读，不代表阅读赞成或被搜索链接到的第三方网页上的内容或立场。
    您应该对使用搜索引擎的结果自行承担风险。
    * 阅读不做任何形式的保证：不保证第三方搜索引擎的搜索结果满足您的要求，不保证搜索服务不中断，不保证搜索结果的安全性、正确性、及时性、合法性。
    因网络状况、通讯线路、第三方网站等任何原因而导致您不能正常使用阅读，阅读不承担任何法律责任。
    阅读尊重并保护所有使用阅读用户的个人隐私权，您注册的用户名、电子邮件地址等个人资料，非经您亲自许可或根据相关法律、法规的强制性规定，阅读不会主动地泄露给第三方。
    * 阅读致力于最大程度地减少网络文学阅读者在自行搜寻过程中的无意义的时间浪费，通过专业搜索展示不同网站中网络文学的最新章节。
    阅读在为广大小说爱好者提供方便、快捷舒适的试读体验的同时，也使优秀网络文学得以迅速、更广泛的传播，从而达到了在一定程度促进网络文学充分繁荣发展之目的。
    阅读鼓励广大小说爱好者通过阅读发现优秀网络小说及其提供商，并建议阅读正版图书。
    任何单位或个人认为通过阅读搜索链接到的第三方网页内容可能涉嫌侵犯其信息网络传播权，应该及时向阅读提出书面权力通知，并提供身份证明、权属证明及详细侵权情况证明。
    阅读在收到上述法律文件后，将会依法尽快断开相关链接内容。
    """

    /// The privacy policy — upstream `assets/privacyPolicy.md`.
    static let privacyPolicyText = """
    * 本应用没有服务端,不收集任何用户信息,只采用了Google Firebase收集崩溃报告和性能报告.
    * 本应用网络同步和备份采用webDav协议,由用户自己提供同步服务.
    * 存储权限用来打开本地文件和本地备份恢复.
    * 其它一些权限是Google Firebase需要.
    * 本应用为开源软件,内置js引擎,因书源调用js发生的任何问题由用户自行承担.
    """
}

// MARK: - The Markdown viewer

/// The Markdown viewer — the port of the upstream's `TextDialog.Mode.MD`.
public struct MarkdownView: View {

    private let source: String
    private let title: String

    public init(title: String, markdown: String) {
        self.title = title
        self.source = markdown
    }

    public init(document: AboutDocument) {
        self.init(title: document.title, markdown: document.text)
    }

    public var body: some View {
        ScrollView {
            MarkdownBody(markdown: source)
        }
        .navigationTitle(title)
    }
}

/// The body of a Markdown document — the blocks of the upstream's
/// `TextDialog.Mode.MD` without the surrounding scroll view.
public struct MarkdownBody: View {

    private let source: String

    public init(markdown: String) {
        self.source = markdown
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Markdown.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(text)
                        .font(headingFont(level))
                        .bold()
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: 14))
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(text)
                            .font(.system(size: 14))
                    }
                case .numbered(let number, let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(number).")
                        Text(text)
                            .font(.system(size: 14))
                    }
                case .quote(let text):
                    Text(text)
                        .font(.system(size: 14))
                        .padding(.leading, 10)
                case .code(let text):
                    Text(text)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                case .divider:
                    Divider()
                case .link(let text, let url):
                    Link(destination: URL(string: url) ?? URL(string: "https://github.com/gedoor/legado")!) {
                        Text(text)
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 22)
        case 2: return .system(size: 19)
        case 3: return .system(size: 17)
        default: return .system(size: 15)
        }
    }
}

// MARK: - The crash logs

/// The crash logs — upstream `ui/about/CrashLogsDialog.kt`.
///
/// The upstream reads the crash files of the cache directory; the port keeps
/// the log in memory (`AppLog`), so the crashes are the entries that carry an
/// error.
public struct CrashLogView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var entries: [AppLog.Entry] = []

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("没有崩溃记录")
                        .foregroundColor(.secondary)
                }
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLog.formatTime(entry.time))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(entry.message)
                    if let error = entry.errorDescription {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("崩溃日志")
        .onAppear {
            entries = AppLog.shared.logs.filter { $0.errorDescription != nil }
        }
    }
}

// MARK: - Saving the logs

/// The log exporter — upstream `AboutFragment.saveLog` (L124-141).
public enum LogExporter {

    /// The name of the file — upstream `logs.zip`.
    public static let fileName = "logs.zip"

    /// Writes the log into the backup directory.
    ///
    /// The upstream zips the log files, the crash files and the logcat into
    /// `logs.zip`; the port writes the in-memory log as a text file.
    @discardableResult
    public static func export(to directory: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        var text = ""
        for entry in AppLog.shared.logs {
            text += "[\(formatter.string(from: entry.time))] \(entry.message)\n"
            if let error = entry.errorDescription {
                text += "\(error)\n"
            }
        }
        let file = directory.appendingPathComponent("logs.txt")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
