//
//  Styling.swift
//  LegadoUIShim
//
//  The styling vocabulary of SwiftUI — `Color`, `Font`, the shapes, the
//  alignments and the edge insets.
//
//  See `View.swift` for the rationale of the shim.
//

import Foundation

// MARK: - Color

/// `SwiftUI.Color`.
///
/// `Color` is a `View` in the real SwiftUI (it can be used as a child of a
/// stack), so the shim makes it one too.
public struct Color: Hashable, Sendable, View {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
    public static let clear = Color(white: 0, opacity: 0)
    public static let black = Color(white: 0)
    public static let white = Color(white: 1)
    public static let gray = Color(white: 0.55)
    public static let red = Color(red: 1, green: 0.23, blue: 0.19)
    public static let orange = Color(red: 1, green: 0.58, blue: 0)
    public static let yellow = Color(red: 1, green: 0.8, blue: 0)
    public static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
    public static let mint = Color(red: 0.35, green: 0.85, blue: 0.7)
    public static let teal = Color(red: 0, green: 0.6, blue: 0.6)
    public static let cyan = Color(red: 0, green: 0.75, blue: 0.9)
    public static let blue = Color(red: 0, green: 0.48, blue: 1)
    public static let indigo = Color(red: 0.3, green: 0.3, blue: 0.85)
    public static let purple = Color(red: 0.6, green: 0.35, blue: 0.85)
    public static let pink = Color(red: 1, green: 0.4, blue: 0.7)
    public static let brown = Color(red: 0.55, green: 0.4, blue: 0.25)
    public static let primary = Color(red: 0.2, green: 0.48, blue: 1)
    public static let secondary = Color(white: 0.55)
    public static let accentColor = Color(red: 0.2, green: 0.48, blue: 1)

    /// `SwiftUI.Color.opacity(_:)`.
    public func opacity(_ opacity: Double) -> Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
    public var body: Never { fatalError("Color has no body") }
}

/// `SwiftUI.RGBColorSpace`.
public enum RGBColorSpace: Sendable {
    case sRGB
    case displayP3
}

// MARK: - Font

/// `SwiftUI.Font`.
public struct Font: Hashable, Sendable {
    public enum TextStyle: Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption
    }
    public enum Weight: Hashable, Sendable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }
    public enum Design: Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }
    public let style: TextStyle?
    public let size: Double?
    public let weight: Weight?
    public let design: Design?

    public static let largeTitle = Font(style: .largeTitle)
    public static let title = Font(style: .title)
    public static let title2 = Font(style: .title2)
    public static let title3 = Font(style: .title3)
    public static let headline = Font(style: .headline)
    public static let subheadline = Font(style: .subheadline)
    public static let body = Font(style: .body)
    public static let callout = Font(style: .callout)
    public static let footnote = Font(style: .footnote)
    public static let caption = Font(style: .caption)
    public static let caption2 = Font(style: .caption)

    public static func system(size: Double, weight: Weight = .regular, design: Design = .default) -> Font {
        Font(style: nil, size: size, weight: weight, design: design)
    }
    public static func system(_ style: TextStyle, design: Design = .default) -> Font {
        Font(style: style, size: nil, weight: nil, design: design)
    }
    public static func custom(_ name: String, size: Double) -> Font {
        Font(style: nil, size: size, weight: nil, design: nil)
    }
    public static func monospaced(_ style: TextStyle) -> Font { Font(style: style, size: nil, weight: nil, design: .monospaced) }
    public static func monospacedDigit(_ style: TextStyle) -> Font { Font(style: style, size: nil, weight: nil, design: .monospaced) }

    public init(style: TextStyle?, size: Double?, weight: Weight?, design: Design?) {
        self.style = style
        self.size = size
        self.weight = weight
        self.design = design
    }
    public init(style: TextStyle) {
        self.style = style
        self.size = nil
        self.weight = nil
        self.design = nil
    }
    public func weight(_ weight: Weight) -> Font { Font(style: style, size: size, weight: weight, design: design) }
    public func bold() -> Font { Font(style: style, size: size, weight: .bold, design: design) }
    public func italic() -> Font { self }
    public func monospacedDigit() -> Font { self }
}

// MARK: - Shapes

/// `SwiftUI.Shape`.
public protocol Shape {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

/// `SwiftUI.Rectangle`.
public struct Rectangle: Shape {
    public init() {}
    public var body: Never { fatalError("Rectangle has no body") }
}

/// `SwiftUI.RoundedRectangle`.
public struct RoundedRectangle: Shape {
    public let cornerRadius: Double
    public init(cornerRadius: Double, style: RoundedCornerStyle = .circular) { self.cornerRadius = cornerRadius }
    public var body: Never { fatalError("RoundedRectangle has no body") }
}

/// `SwiftUI.RoundedCornerStyle`.
public enum RoundedCornerStyle: Sendable {
    case circular
    case continuous
}

/// `SwiftUI.Capsule`.
public struct Capsule: Shape {
    public init(style: RoundedCornerStyle = .circular) {}
    public var body: Never { fatalError("Capsule has no body") }
}

/// `SwiftUI.Circle`.
public struct Circle: Shape {
    public init() {}
    public var body: Never { fatalError("Circle has no body") }
}

/// `SwiftUI.Ellipse`.
public struct Ellipse: Shape {
    public init() {}
    public var body: Never { fatalError("Ellipse has no body") }
}

// MARK: - Geometry

/// `SwiftUI.EdgeInsets`.
public struct EdgeInsets: Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    public static let zero = EdgeInsets()
}

/// `SwiftUI.Edge.Set`.
public struct Edge: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let top = Edge(rawValue: 1 << 0)
    public static let leading = Edge(rawValue: 1 << 1)
    public static let bottom = Edge(rawValue: 1 << 2)
    public static let trailing = Edge(rawValue: 1 << 3)
    public static let all: Edge.Set = [top, leading, bottom, trailing]
    public static let horizontal: Edge.Set = [leading, trailing]
    public static let vertical: Edge.Set = [top, bottom]

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let all = Set(rawValue: 15)
        public static let horizontal = Set(rawValue: 1 << 1 | 1 << 3)
        public static let vertical = Set(rawValue: 1 << 0 | 1 << 2)
        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
    }
}

extension Edge.Set: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Edge...) {
        self.init(rawValue: elements.reduce(0) { $0 | $1.rawValue })
    }
}

/// `SwiftUI.HorizontalAlignment`.
public struct HorizontalAlignment: Hashable, Sendable {
    public static let leading = HorizontalAlignment()
    public static let center = HorizontalAlignment()
    public static let trailing = HorizontalAlignment()
}

/// `SwiftUI.VerticalAlignment`.
public struct VerticalAlignment: Hashable, Sendable {
    public static let top = VerticalAlignment()
    public static let center = VerticalAlignment()
    public static let bottom = VerticalAlignment()
    public static let firstTextBaseline = VerticalAlignment()
}

/// `SwiftUI.Alignment`.
public struct Alignment: Hashable, Sendable {
    public let horizontal: HorizontalAlignment
    public let vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

/// `SwiftUI.ContentMode`.
public enum ContentMode: String, Sendable {
    case fit
    case fill
    case unspecified
}

/// `SwiftUI.RedactionReason` is covered by `RedactionReasons`.

// MARK: - Animation

/// `SwiftUI.Animation`.
public struct Animation: Sendable {
    public static let `default` = Animation()
    public static let linear = Animation()
    public static let easeIn = Animation()
    public static let easeOut = Animation()
    public static let easeInOut = Animation()
    public static let spring = Animation()
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func spring(response: Double, dampingFraction: Double) -> Animation { Animation() }
    public init() {}
}

/// `SwiftUI.Transaction`.
public struct Transaction {
    public var animation: Animation?
    public static let `default` = Transaction()
    public init() {}
}

/// `SwiftUI.Animation` is used as a `View` modifier argument; the shim keeps
/// the type simple.

// MARK: - Miscellaneous

/// `SwiftUI.ScrollViewBehavior`.
public struct ScrollViewBehavior: Hashable, Sendable {
    public static let automatic = ScrollViewBehavior()
}

/// `SwiftUI.NavigationBarItem`.
public struct NavigationBarItem: Hashable, Sendable {
    public static let automatic = NavigationBarItem()
    public static let inline = NavigationBarItem()
    public static let large = NavigationBarItem()

    /// `SwiftUI.NavigationBarItem.DisplayMode` — the argument of
    /// `navigationBarTitleDisplayMode(_:)`.
    public struct DisplayMode: Hashable, Sendable {
        public static let automatic = DisplayMode()
        public static let inline = DisplayMode()
        public static let large = DisplayMode()
        public init() {}
    }

    public init() {}
}

/// `SwiftUI.IndexSet` — the Foundation type is reused.

/// `SwiftUI.KeyEquivalent` is not used by the port.
