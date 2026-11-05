//
//  ReaderSettingsView.swift
//  LegadoUI
//
//  The preferences of the reader — upstream `MoreConfigDialog`,
//  `ReadStyleDialog` and `BgTextConfigDialog`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/config/MoreConfigDialog.kt
//  app/src/main/java/io/legado/app/ui/book/read/config/ReadStyleDialog.kt
//  app/src/main/java/io/legado/app/ui/book/read/config/BgTextConfigDialog.kt
//  app/src/main/res/xml/pref_config_read.xml
//  app/src/main/res/values/arrays.xml
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The enumerations of the reader preferences

/// The weight of the text — upstream `R.array.text_font_weight`
/// (normal, bold, light) and `ReadBookConfig.Config.textBold`.
public enum ReaderTextWeight: Int, CaseIterable {
    case normal = 0
    case bold = 1
    case light = 2

    /// The name of the weight.
    public var name: String {
        switch self {
        case .normal: return "正常"
        case .bold: return "粗体"
        case .light: return "细体"
        }
    }
}

/// The position of the chapter title — upstream `Config.titleMode`
/// (`ReadBookConfig.kt:554`: 0 left, 1 centre, 2 hidden).
public enum ReaderTitleMode: Int, CaseIterable {
    case left = 0
    case centre = 1
    case hidden = 2

    /// The name of the position.
    public var name: String {
        switch self {
        case .left: return "居左"
        case .centre: return "居中"
        case .hidden: return "隐藏"
        }
    }
}

/// The indent of the first line of a paragraph — upstream `R.array.indent`.
///
/// The upstream writes the indent as the full-width space repeated
/// (`ReadStyleDialog.kt:120`: `ReadBookConfig.paragraphIndent = "　".repeat(index)`).
public enum ReaderIndentLevel: Int, CaseIterable {
    case none = 0
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    /// The indent of the paragraph.
    public var indent: String {
        String(repeating: "\u{3000}", count: rawValue)
    }

    /// The name of the indent.
    public var name: String {
        rawValue == 0 ? "无" : "\(rawValue) 字"
    }
}

/// The system typefaces of the reader — upstream `SystemTypeface`
/// (sans serif, serif, monospace).
public enum ReaderSystemTypeface: Int, CaseIterable {
    case sansSerif = 0
    case serif = 1
    case monospace = 2

    /// The name of the typeface.
    public var name: String {
        switch self {
        case .sansSerif: return "系统默认"
        case .serif: return "衬线"
        case .monospace: return "等宽"
        }
    }
}

/// The colours the reader offers — the palette of the colour picker of the
/// upstream (`ColorPickerDialog`).
public enum ReaderColorSwatch: String, CaseIterable {
    case black = "#000000"
    case white = "#FFFFFF"
    case grey = "#808080"
    case red = "#FF3B30"
    case orange = "#FF9500"
    case yellow = "#FFCC00"
    case green = "#34C759"
    case blue = "#007AFF"
    case brown = "#8B4513"

    /// The value of the colour.
    public var value: String { rawValue }

    /// The name of the colour.
    public var name: String {
        switch self {
        case .black: return "黑色"
        case .white: return "白色"
        case .grey: return "灰色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .brown: return "棕色"
        }
    }
}

// MARK: - The rows of the reader preferences

/// The style of the text — upstream `ReadStyleDialog`.
///
/// The upstream changes the configuration while the dialog is open
/// (`ReadStyleDialog.kt:147`: `dsbTextSize.onChanged` writes
/// `ReadBookConfig.textSize`).
public struct ReaderStyleRows: View {

    @Binding var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        // `ReadStyleDialog.kt:147` — the size of the text.
        Stepper(value: $config.textSize, in: 10.0...40.0, step: 1) {
            Text("字号 \(Int(config.textSize))")
        }
        // `ReadStyleDialog.kt:147` — the size of the title.
        Stepper(value: $config.titleSize, in: 10.0...40.0, step: 1) {
            Text("标题字号 \(Int(config.titleSize))")
        }
        // `ReadStyleDialog.kt:114` — the weight of the text
        // (`ReadBookConfig.textBold`).
        Picker("字重", selection: $config.textBold) {
            ForEach(ReaderTextWeight.allCases, id: \.rawValue) { weight in
                Text(weight.name).tag(weight.rawValue)
            }
        }
        // `BgTextConfigDialog.kt:208` — the underline of the text.
        Toggle("下划线", isOn: $config.underline)
        // `ReadStyleDialog.kt:151` — the letter spacing.
        Stepper(value: $config.letterSpacing, in: 0.0...0.5, step: 0.05) {
            Text("字间距 \(String(format: "%.2f", config.letterSpacing))")
        }
        // `ReadStyleDialog.kt:155` — the line spacing.
        Stepper(value: $config.lineSpacingExtra, in: 0.0...30.0, step: 1) {
            Text("行距 \(Int(config.lineSpacingExtra))")
        }
        // `ReadStyleDialog.kt:159` — the spacing between two paragraphs.
        Stepper(value: $config.paragraphSpacing, in: 0.0...30.0, step: 1) {
            Text("段距 \(Int(config.paragraphSpacing))")
        }
        // `ReadStyleDialog.kt:120` — the indent of the first line.
        Picker("段落缩进", selection: $config.paragraphIndent) {
            ForEach(ReaderIndentLevel.allCases, id: \.rawValue) { level in
                Text(level.name).tag(level.indent)
            }
        }
        // `ReadBookConfig.kt:554` — the position of the title.
        Picker("标题位置", selection: $config.titleMode) {
            ForEach(ReaderTitleMode.allCases, id: \.rawValue) { mode in
                Text(mode.name).tag(mode.rawValue)
            }
        }
        // `ReadStyleDialog.kt:136` — the animation of the page turn.
        Picker("翻页动画", selection: $config.pageAnim) {
            ForEach(PageTurnStyle.allCases, id: \.rawValue) { style in
                Text(style.name).tag(style.rawValue)
            }
        }
    }
}

/// The page of the reader — upstream `pref_config_read.xml` and the padding
/// dialog of the style (`ReadStyleDialog.kt:123`).
public struct ReaderPageRows: View {

    @Binding var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        // `pref_config_read.xml` — `textFullJustify`.
        Toggle("两端对齐", isOn: $config.textFullJustify)
        // `pref_config_read.xml` — `textBottomJustify`.
        Toggle("底部对齐", isOn: $config.textBottomJustify)
        // `pref_config_read.xml` — `useZhLayout`.
        Toggle("中文排版", isOn: $config.useZhLayout)
        // `pref_config_read.xml` — `doubleHorizontalPage`.
        Toggle("双页显示", isOn: $config.doublePage)
        // `ReadBookConfig.Config.headerMode` — the header of the page.
        Toggle("显示页眉", isOn: $config.showHeader)
        // `ReadBookConfig.Config.footerMode` — the footer of the page.
        Toggle("显示页脚", isOn: $config.showFooter)
        // `ReadBookConfig.Config.paddingTop` and the other paddings.
        Stepper(value: $config.paddingTop, in: 0.0...60.0, step: 1) {
            Text("上边距 \(Int(config.paddingTop))")
        }
        Stepper(value: $config.paddingBottom, in: 0.0...60.0, step: 1) {
            Text("下边距 \(Int(config.paddingBottom))")
        }
        Stepper(value: $config.paddingLeft, in: 0.0...60.0, step: 1) {
            Text("左边距 \(Int(config.paddingLeft))")
        }
        Stepper(value: $config.paddingRight, in: 0.0...60.0, step: 1) {
            Text("右边距 \(Int(config.paddingRight))")
        }
        // `ReadBookConfig.Config.titleTopSpacing` and `titleBottomSpacing`.
        Stepper(value: $config.titleTopSpacing, in: 0.0...60.0, step: 1) {
            Text("标题上间距 \(Int(config.titleTopSpacing))")
        }
        Stepper(value: $config.titleBottomSpacing, in: 0.0...60.0, step: 1) {
            Text("标题下间距 \(Int(config.titleBottomSpacing))")
        }
        // `ReadBookConfig.headerMode` and `footerMode` — the visibility of the
        // tip rows.
        Picker("页眉模式", selection: $config.headerMode) {
            ForEach(ReaderTipMode.allCases, id: \.rawValue) { mode in
                Text(ReaderTipModeRow.name(of: mode)).tag(mode.rawValue)
            }
        }
        Picker("页脚模式", selection: $config.footerMode) {
            ForEach(ReaderTipMode.allCases, id: \.rawValue) { mode in
                Text(ReaderTipModeRow.name(of: mode)).tag(mode.rawValue)
            }
        }
        // `ReadBookConfig.tipHeaderLeft` … `tipFooterRight` — the six tip
        // slots of the page. A tip may be used only once — the upstream
        // `TipConfigDialog.clearRepeat` removes it from the other slots.
        Picker("页眉左侧", selection: tipBinding(\.tipHeaderLeft)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        Picker("页眉中间", selection: tipBinding(\.tipHeaderMiddle)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        Picker("页眉右侧", selection: tipBinding(\.tipHeaderRight)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        Picker("页脚左侧", selection: tipBinding(\.tipFooterLeft)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        Picker("页脚中间", selection: tipBinding(\.tipFooterMiddle)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        Picker("页脚右侧", selection: tipBinding(\.tipFooterRight)) {
            ForEach(ReaderTipType.pickerOrder, id: \.rawValue) { type in
                Text(type.displayName).tag(type.rawValue)
            }
        }
        // `TipConfigDialog.kt:187-220` — the colour of the tips and the
        // colour of the divider.
        ReaderTipColorField(
            title: "提示文字颜色",
            value: $config.tipColor,
            options: [
                ReaderTipColorField.Option(name: "与正文同色", value: 0)
            ]
        )
        ReaderTipColorField(
            title: "分割线颜色",
            value: $config.tipDividerColor,
            options: [
                ReaderTipColorField.Option(name: "默认", value: -1),
                ReaderTipColorField.Option(name: "与正文同色", value: 0)
            ]
        )
    }

    /// The binding of a tip slot — the repeated tips are cleared first.
    private func tipBinding(_ keyPath: WritableKeyPath<ReaderConfig, Int>) -> Binding<Int> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { newValue in
                config.clearRepeatedTip(newValue)
                config[keyPath: keyPath] = newValue
            }
        )
    }
}

/// The names of the tip modes — upstream `ReadTipConfig` (the header has
/// three states, the footer two).
public enum ReaderTipModeRow {

    /// The name of a mode.
    public static func name(of mode: ReaderTipMode) -> String {
        switch mode {
        case .automatic: return "自动"
        case .always: return "始终显示"
        case .never: return "隐藏"
        }
    }
}

/// The colours of the reader — upstream `BgTextConfigDialog`.
///
/// The upstream opens a colour picker for the text and for the background
/// (`BgTextConfigDialog.kt:229`) and a slider for the opacity of the
/// background (`BgTextConfigDialog.kt:256`).
public struct ReaderColorRows: View {

    @Binding var config: ReaderConfig

    public init(config: Binding<ReaderConfig>) {
        _config = config
    }

    public var body: some View {
        // `BgTextConfigDialog.kt:229` — the colour of the background.
        ReaderColorField(title: "背景颜色", value: $config.backgroundColor)
        // `Config.bgStrNight` — the background of the night.
        ReaderColorField(title: "夜间背景颜色", value: $config.backgroundColorNight)
        // `BgTextConfigDialog.kt:229` — the colour of the text.
        ReaderColorField(title: "文字颜色", value: $config.textColor)
        // `Config.textColorNight` — the text of the night.
        ReaderColorField(title: "夜间文字颜色", value: $config.textColorNight)
        // `BgTextConfigDialog.kt:256` — the opacity of the background.
        Stepper("背景透明度 \(config.backgroundAlpha)%", value: $config.backgroundAlpha, in: 0...100)
    }
}

/// One colour of the reader — upstream `ColorPickerDialog`.
///
/// The upstream has no text field for the colours, the port writes the
/// hexadecimal value and offers the palette of the swatches.
public struct ReaderColorField: View {

    let title: String
    @Binding var value: String

    public init(title: String, value: Binding<String>) {
        self.title = title
        _value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField("#FFFFFF", text: $value)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                ForEach(ReaderColorSwatch.allCases, id: \.rawValue) { swatch in
                    Button {
                        value = swatch.value
                    } label: {
                        ColorHex.color(swatch.value, fallback: .white)
                            .frame(width: 22, height: 22)
                    }
                }
            }
        }
    }
}

/// The font of the reader — upstream `ReadStyleDialog.kt:117` (the font
/// picker) and `ChapterProvider.getTypeface` (`ChapterProvider.kt:854`).
///
/// The upstream keeps the font of the style in `Config.textFont`; the port
/// keeps the path of the font in the `fontFolder` preference, the way the
/// reader already reads it (`ReaderController.resolvedFonts`).
public struct ReaderFontRows: View {

    let settings: AppSettings
    let onChange: () -> Void

    public init(settings: AppSettings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    public var body: some View {
        Picker("系统字体", selection: Binding(
            get: { settings.systemTypefaces },
            set: { value in
                settings.systemTypefaces = value
                onChange()
            }
        )) {
            ForEach(ReaderSystemTypeface.allCases, id: \.rawValue) { face in
                Text(face.name).tag(face.rawValue)
            }
        }
        HStack {
            Text("字体文件")
            Spacer()
            TextField("字体路径", text: Binding(
                get: { settings.string(.fontFolder) ?? "" },
                set: { value in
                    settings.set(value.isEmpty ? nil : value, for: .fontFolder)
                    onChange()
                }
            ))
            .multilineTextAlignment(.trailing)
        }
    }
}

/// The Chinese converter of the reader — upstream `ReadStyleDialog.kt:110`
/// (the converter is unloaded and the content is laid out again).
public struct ReaderConverterRow: View {

    @State private var selection: Int
    let onChange: (ChineseConversionMode) -> Void

    public init(selection: Int, onChange: @escaping (ChineseConversionMode) -> Void) {
        _selection = State(wrappedValue: selection)
        self.onChange = onChange
    }

    public var body: some View {
        Picker("繁简转换", selection: Binding(
            get: { selection },
            set: { value in
                selection = value
                guard let mode = ChineseConversionMode(rawValue: value) else { return }
                onChange(mode)
            }
        )) {
            ForEach(ChineseConversionMode.allCases, id: \.rawValue) { mode in
                Text(ReaderConverterRow.name(of: mode)).tag(mode.rawValue)
            }
        }
    }

    /// The name of a converter.
    public static func name(of mode: ChineseConversionMode) -> String {
        switch mode {
        case .off: return "关闭"
        case .traditionalToSimplified: return "繁转简"
        case .simplifiedToTraditional: return "简转繁"
        }
    }
}

// MARK: - The screens

/// The reading preferences of the app — upstream `pref_config_read.xml`.
///
/// Every row of the upstream's preference screen is reproduced: the screen
/// orientation, the screen timeout, the hidden bars, the layout switches, the
/// paging switches, the progress bar, the behaviour switches and the click
/// regions.
public struct ReaderPreferenceRows: View {

    /// The settings of the app — the rows write into them directly (the
    /// upstream writes the preferences on every change).
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        // `pref_config_read.xml` — the screen.
        Picker("屏幕方向", selection: Binding(
            get: { settings.readerScreenDirection },
            set: { settings.readerScreenDirection = $0 }
        )) {
            ForEach(ReaderScreenDirection.allCases) { direction in
                Text(direction.displayName).tag(direction.rawValue)
            }
        }
        Picker("屏幕常亮", selection: Binding(
            get: { settings.keepLight },
            set: { settings.keepLight = $0 }
        )) {
            ForEach(ReaderScreenTimeout.allCases) { timeout in
                Text(timeout.displayName).tag(timeout.rawValue)
            }
        }
        Toggle("隐藏状态栏", isOn: Binding(
            get: { settings.hideStatusBar },
            set: { settings.hideStatusBar = $0 }
        ))
        Toggle("隐藏导航栏", isOn: Binding(
            get: { settings.hideNavigationBar },
            set: { settings.hideNavigationBar = $0 }
        ))
        Toggle("避开刘海屏", isOn: Binding(
            get: { settings.paddingDisplayCutouts },
            set: { settings.paddingDisplayCutouts = $0 }
        ))
        // The layout.
        Toggle("文字对齐到左边", isOn: Binding(
            get: { settings.readBodyToLh },
            set: { settings.readBodyToLh = $0 }
        ))
        Picker("双页显示", selection: Binding(
            get: { settings.doublePageHorizontal },
            set: { settings.doublePageHorizontal = $0 }
        )) {
            ForEach(ReaderDoublePageMode.allCases) { mode in
                Text(mode.displayName).tag(mode.rawValue)
            }
        }
        Toggle("中文排版", isOn: Binding(
            get: { settings.useZhLayout },
            set: { settings.useZhLayout = $0 }
        ))
        Toggle("底部对齐", isOn: Binding(
            get: { settings.textBottomJustify },
            set: { settings.textBottomJustify = $0 }
        ))
        // The paging.
        Picker("进度条行为", selection: Binding(
            get: { settings.progressBarBehavior },
            set: { settings.progressBarBehavior = $0 }
        )) {
            ForEach(ReaderProgressBarBehavior.allCases) { behavior in
                Text(behavior.displayName).tag(behavior.rawValue)
            }
        }
        Toggle("鼠标滚轮翻页", isOn: Binding(
            get: { settings.mouseWheelPage },
            set: { settings.mouseWheelPage = $0 }
        ))
        Toggle("音量键翻页", isOn: Binding(
            get: { settings.volumeKeyPage },
            set: { settings.volumeKeyPage = $0 }
        ))
        Toggle("朗读时音量键翻页", isOn: Binding(
            get: { settings.volumeKeyPageOnPlay },
            set: { settings.volumeKeyPageOnPlay = $0 }
        ))
        Toggle("长按按键翻页", isOn: Binding(
            get: { settings.keyPageOnLongPress },
            set: { settings.keyPageOnLongPress = $0 }
        ))
        Stepper(value: Binding(
            get: { Double(settings.pageTouchSlop) },
            set: { settings.pageTouchSlop = max(0, Int($0)) }
        ), in: 0...100, step: 5) {
            Text("翻页触摸阈值 \(settings.pageTouchSlop)")
        }
        Toggle("滚动翻页无动画", isOn: Binding(
            get: { settings.noAnimScrollPage },
            set: { settings.noAnimScrollPage = $0 }
        ))
        Toggle("点击预览图片", isOn: Binding(
            get: { settings.previewImageByClick },
            set: { settings.previewImageByClick = $0 }
        ))
        Toggle("优化渲染", isOn: Binding(
            get: { settings.optimizeRender },
            set: { settings.optimizeRender = $0 }
        ))
        // The behaviour.
        Toggle("自动换源", isOn: Binding(
            get: { settings.autoChangeSource },
            set: { settings.autoChangeSource = $0 }
        ))
        Toggle("允许选择文字", isOn: Binding(
            get: { settings.textSelectAble },
            set: { settings.textSelectAble = $0 }
        ))
        Toggle("显示亮度调节", isOn: Binding(
            get: { settings.showBrightnessView },
            set: { settings.showBrightnessView = $0 }
        ))
        Toggle("展开更多菜单", isOn: Binding(
            get: { settings.expandTextMenu },
            set: { settings.expandTextMenu = $0 }
        ))
        Toggle("显示阅读标题附加", isOn: Binding(
            get: { settings.showReadTitleAddition },
            set: { settings.showReadTitleAddition = $0 }
        ))
        Toggle("阅读栏样式跟随页面", isOn: Binding(
            get: { settings.readBarStyleFollowPage },
            set: { settings.readBarStyleFollowPage = $0 }
        ))
    }
}

/// The more settings of the reader — upstream `MoreConfigDialog`.
///
/// The upstream builds the screen from `pref_config_read.xml`
/// (`MoreConfigDialog.kt:86`) and writes every change into the preferences
/// (`MoreConfigDialog.kt:113`: `onSharedPreferenceChanged`).
public struct ReaderSettingsView: View {

    @ObservedObject var controller: ReaderController

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        Form {
            Section("排版") {
                ReaderStyleRows(config: configBinding)
            }
            // Upstream `dialog_read_book_style.xml` — the check box
            // `cb_share_layout` ("共用布局"): when it is on, every background
            // uses the same layout.
            Section("共用布局") {
                Toggle("共用布局", isOn: Binding(
                    get: { controller.shareLayoutEnabled },
                    set: { value in Task { await controller.setShareLayout(value) } }
                ))
                Text("启用共用布局时所有背景使用同一布局，关闭共用布局则每个背景单独布局")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section("页面") {
                ReaderPageRows(config: configBinding)
            }
            Section("颜色") {
                ReaderColorRows(config: configBinding)
            }
            Section("字体") {
                ReaderFontRows(settings: controller.environment.settings) {
                    Task { await controller.applyReaderSettings { $0 = $0 } }
                }
            }
            Section("文字转换") {
                ReaderConverterRow(selection: controller.configStore.chineseConverterType) { mode in
                    Task { await controller.setChineseConverter(mode) }
                }
            }
            Section("点击区域") {
                // Upstream `ClickActionConfigDialog` — the nine regions of
                // the page.
                NavigationLink("点击区域设置") {
                    ClickRegionEditorView(settings: controller.environment.settings)
                }
            }
            // Upstream `pref_config_read.xml` — the whole preference screen.
            Section("阅读偏好") {
                ReaderPreferenceRows(settings: controller.environment.settings)
            }
            // Upstream `pref_config_read.xml` — the switch
            // `disableReturnKey` (the back key does nothing while the reader
            // menu is hidden).
            Section("更多") {
                Toggle("禁用返回键", isOn: Binding(
                    get: { controller.environment.settings.disableReturnKey },
                    set: { controller.environment.settings.disableReturnKey = $0 }
                ))
            }
        }
        .navigationTitle("更多设置")
    }

    /// The configuration of the running reader — every change is saved
    /// (`ReadStyleDialog.kt:66`: `ReadBookConfig.save()`).
    ///
    /// The upstream edits the layout that is in use — the shared one when the
    /// "共用布局" switch is on (`ReadBookConfig.kt:243`).
    private var configBinding: Binding<ReaderConfig> {
        Binding(
            get: { controller.effectiveConfig },
            set: { updated in
                Task { await controller.applyReaderSettings { $0 = updated } }
            }
        )
    }
}

/// The reader preferences of the app — upstream `MoreConfigDialog`.
///
/// The screen writes the configuration into the preferences of the app, so
/// the reader opens with them.
public struct ReaderPreferencesView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var config: ReaderConfig
    private let store: ReaderConfigStore

    public init(model: LegadoAppModel) {
        self.model = model
        let store = ReaderConfigStore(settings: model.environment.settings)
        self.store = store
        _config = State(wrappedValue: store.load())
    }

    public var body: some View {
        Form {
            Section("排版") {
                ReaderStyleRows(config: $config)
            }
            Section("页面") {
                ReaderPageRows(config: $config)
            }
            Section("颜色") {
                ReaderColorRows(config: $config)
            }
            Section("字体") {
                ReaderFontRows(settings: model.environment.settings) { save() }
            }
            Section("文字转换") {
                ReaderConverterRow(selection: store.chineseConverterType) { mode in
                    store.chineseConverterType = mode.rawValue
                    model.environment.settings.chineseConverterType = mode.rawValue
                }
            }
            // Upstream `pref_config_read.xml` — the whole preference screen.
            Section("阅读偏好") {
                ReaderPreferenceRows(settings: model.environment.settings)
            }
            Section("点击区域") {
                NavigationLink("点击区域设置") {
                    ClickRegionEditorView(settings: model.environment.settings)
                }
            }
        }
        .navigationTitle("阅读设置")
        .onChange(of: config) { _, value in
            store.save(value)
        }
    }

    /// Saves the configuration — the preferences of the reader.
    private func save() {
        store.save(config)
    }
}
