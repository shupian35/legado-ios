#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The colour of the reader's tips — upstream
/// `app/src/main/java/io/legado/app/ui/book/read/config/TipConfigDialog.kt:187-220`.
///
/// The upstream opens the Android colour picker
/// (`ColorPickerDialog.TYPE_CUSTOM`) after a selector with two (or three)
/// entries: the tip colour offers "与正文同色" and "自定义", the divider
/// colour offers "默认", "与正文同色" and "自定义".
///
/// The port cannot show the Android picker, so it offers the same special
/// entries, a palette of swatches and a hexadecimal field.
public struct ReaderTipColorField: View {

    /// One entry of the selector — upstream `R.array.tip_color` /
    /// `R.array.tip_divider_color`.
    public struct Option: Identifiable, Equatable {
        public let name: String
        public let value: Int
        public var id: Int { value }

        public init(name: String, value: Int) {
            self.name = name
            self.value = value
        }
    }

    let title: String
    @Binding var value: Int
    let options: [Option]

    @State private var hexText: String = ""

    public init(title: String, value: Binding<Int>, options: [Option]) {
        self.title = title
        _value = value
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(currentText)
                    .foregroundColor(.secondary)
            }
            // The special entries of the upstream's selector.
            ForEach(options) { option in
                Button {
                    value = option.value
                } label: {
                    HStack {
                        Text(option.name)
                        Spacer()
                        if value == option.value {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            // The palette.
            HStack(spacing: 8) {
                ForEach(ReaderTipColorSwatch.allCases, id: \.rawValue) { swatch in
                    Button {
                        value = swatch.rawValue
                    } label: {
                        ColorHex.color(swatch.hex, fallback: .white)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            // The custom colour — the upstream's colour picker.
            HStack {
                TextField("#FFFFFF", text: $hexText)
                    .multilineTextAlignment(.trailing)
                Button("应用") {
                    if let parsed = ReaderTipColorField.parse(hexText) {
                        value = parsed
                    }
                }
            }
        }
        .onAppear {
            hexText = value > 0 ? String(format: "#%06X", value) : ""
        }
    }

    /// The text of the current value.
    private var currentText: String {
        if let option = options.first(where: { $0.value == value }) {
            return option.name
        }
        return String(format: "#%06X", value)
    }

    /// Parses a hexadecimal colour — upstream `Color.parseColor`.
    public static func parse(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return Int(cleaned, radix: 16)
    }
}

/// The swatches of the tip colours.
public enum ReaderTipColorSwatch: Int, CaseIterable, Identifiable {
    case black = 0
    case darkGray = 0x444444
    case gray = 0x888888
    case lightGray = 0xCCCCCC
    case white = 0xFFFFFF
    case red = 0xFF0000
    case orange = 0xFF8800
    case green = 0x00AA00
    case blue = 0x0000FF
    case purple = 0x8800FF

    public var id: Int { rawValue }

    /// The hexadecimal form of the swatch.
    public var hex: String { String(format: "#%06X", rawValue) }
}
