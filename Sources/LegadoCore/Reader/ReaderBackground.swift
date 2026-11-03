import Foundation

/// The display mode of the app — upstream `AppConfig.isEInkMode` /
/// `isNightTheme`.
///
/// The upstream pref `themeMode` is a STRING: "0" = follow the system,
/// "1" = forced light, "2" = forced dark, "3" = E-Ink. The mode switch
/// order is **E-Ink > night > day** (`AppConfig.isEInkMode` is checked first
/// everywhere).
public enum ReaderDisplayMode: String, CaseIterable, Sendable {
    case day
    case night
    case eInk

    /// Resolves the mode from the `themeMode` pref and the system night mode.
    public static func resolve(themeMode: String, systemNightMode: Bool) -> ReaderDisplayMode {
        switch themeMode {
        case "3": return .eInk
        case "1": return .day
        case "2": return .night
        default: return systemNightMode ? .night : .day
        }
    }
}

/// The background type — upstream `ReadBookConfig.Config.bgType`.
public enum ReaderBackgroundType: Int, CaseIterable, Sendable {
    /// A solid colour.
    case color = 0
    /// A bundled asset image (`assets/bg/<name>`).
    case asset = 1
    /// A user image (`<externalFiles>/bg/<name>`).
    case file = 2
}

/// The reader background preset — upstream `ReadBookConfig.Config`.
///
/// Only the background related fields are ported; the typography fields live
/// in `ReaderConfig`.
public struct ReaderBackgroundPreset: Codable, Equatable, Sendable {

    public var name: String
    /// The day background (a colour or a file name).
    public var bgStr: String
    public var bgStrNight: String
    public var bgStrEInk: String
    /// The background opacity in percent.
    public var bgAlpha: Int
    public var bgType: Int
    public var bgTypeNight: Int
    public var bgTypeEInk: Int
    public var textColor: String
    public var textColorNight: String
    public var textColorEInk: String

    public init(
        name: String = "",
        bgStr: String = "#EEEEEE",
        bgStrNight: String = "#000000",
        bgStrEInk: String = "#FFFFFF",
        bgAlpha: Int = 100,
        bgType: Int = 0,
        bgTypeNight: Int = 0,
        bgTypeEInk: Int = 0,
        textColor: String = "#3E3D3B",
        textColorNight: String = "#ADADAD",
        textColorEInk: String = "#000000"
    ) {
        self.name = name
        self.bgStr = bgStr
        self.bgStrNight = bgStrNight
        self.bgStrEInk = bgStrEInk
        self.bgAlpha = bgAlpha
        self.bgType = bgType
        self.bgTypeNight = bgTypeNight
        self.bgTypeEInk = bgTypeEInk
        self.textColor = textColor
        self.textColorNight = textColorNight
        self.textColorEInk = textColorEInk
    }

    /// The upstream default preset "微信读书" (`assets/defaultData/readConfig.json`).
    public static let weixinRead = ReaderBackgroundPreset(
        name: "微信读书",
        bgStr: "#ffc0edc6",
        bgStrNight: "#000000",
        bgStrEInk: "#FFFFFF",
        bgAlpha: 100,
        bgType: 0,
        bgTypeNight: 0,
        bgTypeEInk: 0,
        textColor: "#ff0b0b0b",
        textColorNight: "#ADADAD",
        textColorEInk: "#000000"
    )

    /// The background value of the given mode — upstream `curBgStr()`.
    public func backgroundString(for mode: ReaderDisplayMode) -> String {
        switch mode {
        case .day: return bgStr
        case .night: return bgStrNight
        case .eInk: return bgStrEInk
        }
    }

    /// The background type of the given mode — upstream `curBgType()`.
    public func backgroundType(for mode: ReaderDisplayMode) -> ReaderBackgroundType {
        let raw: Int
        switch mode {
        case .day: raw = bgType
        case .night: raw = bgTypeNight
        case .eInk: raw = bgTypeEInk
        }
        return ReaderBackgroundType(rawValue: raw) ?? .color
    }

    /// The text colour of the given mode — upstream `curTextColor()`.
    public func textColorString(for mode: ReaderDisplayMode) -> String {
        switch mode {
        case .day: return textColor
        case .night: return textColorNight
        case .eInk: return textColorEInk
        }
    }
}

/// The resolved background of the reader — upstream
/// `ReadBookConfig.curBgDrawable(width, height)`.
public enum ReaderBackground {

    /// The background file directory — upstream `<externalFiles>/bg`.
    public static let backgroundDirectoryName = "bg"

    /// The path of a user background image.
    ///
    /// Upstream `ReadBookConfig.getBgPath`: the preset stores only the FILE
    /// NAME; the path is `<externalFiles>/bg/<name>` unless the value already
    /// contains a separator.
    public static func filePath(for value: String, root: URL) -> URL {
        if value.contains("/") || value.contains("\\") {
            return URL(fileURLWithPath: value)
        }
        return root.appendingPathComponent(backgroundDirectoryName, isDirectory: true)
            .appendingPathComponent(value)
    }

    /// The opacity of the background — upstream `upBgAlpha`:
    /// `(bgAlpha / 100f * 255)`.
    public static func alpha(for preset: ReaderBackgroundPreset) -> Double {
        min(1, max(0, Double(preset.bgAlpha) / 100.0))
    }

    /// The mean colour of a background image.
    ///
    /// Upstream `BitmapUtils.getMeanColor()` samples the region
    /// x ∈ [0 %, 100 %], y ∈ [70 %, 100 %] (3000 samples) and adds 3 to each
    /// channel. The port computes the same value from the raw pixels.
    public static func meanColor(of pixels: [UInt8], width: Int, height: Int) -> (r: Int, g: Int, b: Int)? {
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return nil }
        var sumR = 0
        var sumG = 0
        var sumB = 0
        var count = 0
        for i in 0..<100 {
            let x = min(width - 1, i * width / 100)
            for j in 70..<100 {
                let y = min(height - 1, j * height / 100)
                let offset = (y * width + x) * 4
                sumR += Int(pixels[offset])
                sumG += Int(pixels[offset + 1])
                sumB += Int(pixels[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (sumR / count + 3, sumG / count + 3, sumB / count + 3)
    }
}
