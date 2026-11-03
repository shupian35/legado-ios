//
//  ThemeSupport.swift
//  LegadoUI
//
//  The bridge between the platform independent theme / font descriptions of
//  `LegadoCore` and the SwiftUI types.
//
//  The file is compiled on every platform: the real SwiftUI on Apple, the
//  shim everywhere else (see `Sources/LegadoUIShim/View.swift`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

import Foundation
import LegadoCore

/// Parses the `#RRGGBB` / `#AARRGGBB` colour strings of the upstream themes.
public enum ColorHex {

    /// Parses a hex colour.
    ///
    /// Returns `nil` for a malformed value, in which case the caller keeps
    /// the default colour.
    public static func parse(_ text: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.allSatisfy({ $0.isHexDigit }) else { return nil }
        let digits = Array(value)
        let byte: (Int) -> Int? = { index in
            guard index + 1 < digits.count else { return nil }
            return Int(String(digits[index...index + 1]), radix: 16)
        }
        switch digits.count {
        case 6:
            guard let r = byte(0), let g = byte(2), let b = byte(4) else { return nil }
            return (Double(r) / 255, Double(g) / 255, Double(b) / 255, 1)
        case 8:
            guard let a = byte(0), let r = byte(2), let g = byte(4), let b = byte(6) else { return nil }
            return (Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
        default:
            return nil
        }
    }

    /// The SwiftUI colour of a hex string.
    public static func color(_ text: String, fallback: Color = .gray) -> Color {
        guard let components = parse(text) else { return fallback }
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }
}

extension AppTheme {

    /// The primary colour.
    public var primary: Color { ColorHex.color(primaryColor, fallback: .brown) }
    /// The accent colour.
    public var accent: Color { ColorHex.color(accentColor, fallback: .red) }
    /// The background colour.
    public var background: Color { ColorHex.color(backgroundColor, fallback: .white) }
    /// The colour of the bottom bar.
    public var bottomBackgroundColor: Color { ColorHex.color(bottomBackground, fallback: .white) }
}

extension ReaderFontDescriptor {

    /// The SwiftUI font of the descriptor.
    public var swiftUIFont: Font {
        let weight: Font.Weight
        switch self.weight {
        case .light: weight = .light
        case .regular: weight = .regular
        case .bold: weight = .bold
        case .black: weight = .black
        }
        switch family {
        case .file:
            if let name = filePath, !name.isEmpty {
                return Font.custom((name as NSString).lastPathComponent, size: size)
            }
            return Font.system(size: size, weight: weight)
        case .serif:
            return Font.custom("Songti SC", size: size)
        case .monospace:
            return Font.custom("Menlo", size: size)
        case .system:
            return Font.system(size: size, weight: weight)
        }
    }
}

#if canImport(UIKit) && !os(watchOS)

extension ReaderFontDescriptor {

    /// The UIKit font of the descriptor.
    ///
    /// The size and the boldness may be overridden — the reader measures the
    /// title and the body with different styles.
    public func uiFont(size overrideSize: Double? = nil, bold: Bool? = nil) -> UIFont {
        let pointSize = overrideSize ?? size
        let isBold = bold ?? (weight == .bold || weight == .black)
        let weight: UIFont.Weight
        switch self.weight {
        case .light: weight = .light
        case .regular: weight = .regular
        case .bold: weight = .bold
        case .black: weight = .black
        }
        let fontWeight = isBold ? (weight == .light ? UIFont.Weight.semibold : weight) : weight
        switch family {
        case .file:
            if let name = filePath, !name.isEmpty {
                let face = (name as NSString).deletingPathExtension
                if let custom = UIFont(name: face, size: pointSize) {
                    return custom
                }
            }
            return UIFont.systemFont(ofSize: pointSize, weight: fontWeight)
        case .serif:
            if let serif = UIFont(name: "Songti SC", size: pointSize) {
                return serif
            }
            return UIFont.systemFont(ofSize: pointSize, weight: fontWeight)
        case .monospace:
            if let mono = UIFont(name: "Menlo", size: pointSize) {
                return mono
            }
            return UIFont.systemFont(ofSize: pointSize, weight: fontWeight)
        case .system:
            return UIFont.systemFont(ofSize: pointSize, weight: fontWeight)
        }
    }
}

#endif
