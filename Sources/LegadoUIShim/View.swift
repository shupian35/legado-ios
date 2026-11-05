//
//  View.swift
//  LegadoUIShim
//
//  A tiny stand-in for SwiftUI.
//
//  SwiftUI only exists on Apple platforms, so the shared UI layer of the port
//  (`Sources/LegadoUI`) could otherwise only ever be compiled on a Mac. This
//  module re-implements the subset of SwiftUI the port uses so that the very
//  same view sources type-check on Linux — which is what the CI job and the
//  local `swift build` do.
//
//  The shim is a *development* tool: it never renders anything. It exists to
//  catch type errors in the view layer early.
//
//  Upstream reference: none — this file has no Android counterpart.
//

import Foundation

// MARK: - View

/// The root of the view protocol — mirrors `SwiftUI.View`.
public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Never { fatalError("Never has no body") }
}

/// The empty view — `SwiftUI.EmptyView`.
public struct EmptyView: View {
    public init() {}
    public var body: Never { fatalError("EmptyView has no body") }
}

/// The type-erased view — `SwiftUI.AnyView`.
///
/// The generic parameter is deliberately unconstrained: the `ViewBuilder`
/// helpers receive the opaque result of a modifier chain, which cannot be
/// matched against a `View`-constrained parameter.
public struct AnyView: View {
    private let erased: Any
    public init<V>(_ view: V) { erased = view }
    public var body: Never { fatalError("AnyView has no body") }
}

/// A view with an arbitrary modifier applied — the shim's equivalent of the
/// hundreds of `some View` returning modifiers of SwiftUI.
public struct ModifiedView<Content: View>: View {
    public let content: Content
    public init(_ content: Content) { self.content = content }
    public var body: some View { content }
}

/// A tuple of views — the result of a `ViewBuilder` with several children.
public struct TupleView<T>: View {
    public let value: T
    public init(_ value: T) { self.value = value }
    public var body: Never { fatalError("TupleView has no body") }
}

// MARK: - ViewBuilder

/// The result builder of SwiftUI — `SwiftUI.ViewBuilder`.
@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C0: View>(_ c0: C0) -> C0 { c0 }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> { TupleView((c0, c1)) }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> { TupleView((c0, c1, c2)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> { TupleView((c0, c1, c2, c3)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> { TupleView((c0, c1, c2, c3, c4)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> { TupleView((c0, c1, c2, c3, c4, c5)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> { TupleView((c0, c1, c2, c3, c4, c5, c6)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View, C15: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14, _ c15: C15) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14, C15)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View, C15: View, C16: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14, _ c15: C15, _ c16: C16) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14, C15, C16)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View, C15: View, C16: View, C17: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14, _ c15: C15, _ c16: C16, _ c17: C17) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14, C15, C16, C17)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View, C15: View, C16: View, C17: View, C18: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14, _ c15: C15, _ c16: C16, _ c17: C17, _ c18: C18) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14, C15, C16, C17, C18)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View, C11: View, C12: View, C13: View, C14: View, C15: View, C16: View, C17: View, C18: View, C19: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10, _ c11: C11, _ c12: C12, _ c13: C13, _ c14: C14, _ c15: C15, _ c16: C16, _ c17: C17, _ c18: C18, _ c19: C19) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, C11, C12, C13, C14, C15, C16, C17, C18, C19)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19)) }

    // An optional child is wrapped in `AnyView` (real SwiftUI keeps the
    // optional and adds optional-aware `buildBlock` overloads). The shim only
    // has to type-check, so the wrapper is enough.
    //
    // NOTE: the parameter is `Any` on purpose — a modifier chain returns an
    // opaque `some View`, and such an opaque type cannot be bound to a generic
    // parameter of a result-builder transform (the solver reports "generic
    // parameter 'C' could not be inferred").
    public static func buildIf(_ content: Any?) -> AnyView {
        if let content { return AnyView(content) }
        return AnyView(EmptyView())
    }
    public static func buildOptional(_ content: Any?) -> AnyView {
        if let content { return AnyView(content) }
        return AnyView(EmptyView())
    }
    // The `if`/`else` result is erased to `AnyView`: the generic
    // `ConditionalContent<T, F>` form needs both branch types, and the
    // compiler cannot infer `F` for `if let … { } else if let … { }`.
    public static func buildEither<T: View>(first: T) -> AnyView { AnyView(first) }
    public static func buildEither<F: View>(second: F) -> AnyView { AnyView(second) }
    public static func buildLimitedAvailability<C: View>(_ content: C) -> AnyView { AnyView(content) }
}

/// The result of an `if`/`else` inside a `ViewBuilder`.
public struct ConditionalContent<TrueContent: View, FalseContent: View>: View {
    let first: TrueContent?
    let second: FalseContent?
    public var body: Never { fatalError("ConditionalContent has no body") }
}

// MARK: - Primitives

/// `SwiftUI.Text`.
public struct Text: View {
    public let content: String
    public init(_ content: String) { self.content = content }
    public init<S: StringProtocol>(_ content: S) { self.content = String(content) }
    public init(verbatim content: String) { self.content = content }
    public init(redaction: RedactionReasons) { content = "" }
    public var body: Never { fatalError("Text has no body") }
    public static func + (lhs: Text, rhs: Text) -> Text { Text(lhs.content + rhs.content) }
}

/// `SwiftUI.RedactionReasons`.
public struct RedactionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
    public static let privacy = RedactionReasons(rawValue: 1 << 1)
}

/// `SwiftUI.Image`.
public struct Image: View {

    /// The interpolation of a resizable image.
    public enum Interpolation {
        case none, low, medium, high
    }

    public let name: String
    public let systemName: String?
    public init(_ name: String) { self.name = name; systemName = nil }
    public init(systemName: String) { self.name = systemName; self.systemName = systemName }
    /// `SwiftUI.Image(uiImage:)` — the image is erased, the shim never renders.
    public init(uiImage: AnyObject) { self.name = "uiImage"; systemName = nil }
    /// `SwiftUI.Image(nsImage:)` — the image is erased, the shim never renders.
    public init(nsImage: AnyObject) { self.name = "nsImage"; systemName = nil }
    public func resizable() -> Image { self }
    public func aspectRatio(_ ratio: Double? = nil, contentMode: ContentMode) -> Image { self }
    public func interpolation(_ interpolation: Interpolation) -> Image { self }
    public var body: Never { fatalError("Image has no body") }
}

/// `SwiftUI.AsyncImage`.
///
/// The content closure returns an `AnyView` so that the SAME call site works
/// with the real SwiftUI (where the closure is a `@ViewBuilder`) and with the
/// shim (where the two branches have different types).
public struct AsyncImage: View {
    public enum Phase {
        case empty
        case success(Image)
        case failure(Error)
    }
    public init(url: URL?, content: @escaping (Phase) -> AnyView) {}
    public var body: Never { fatalError("AsyncImage has no body") }
}

/// `SwiftUI.Button`.
public struct Button: View {
    public let action: () -> Void
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> some View) { self.action = action }
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> some View) { self.action = action }
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) { self.action = action }
    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) { self.action = action }
    public var body: Never { fatalError("Button has no body") }
}

/// `SwiftUI.ButtonRole`.
public enum ButtonRole: Sendable {
    case destructive
    case cancel
}

/// `SwiftUI.Toggle`.
public struct Toggle: View {
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> some View) {}
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {}
    public var body: Never { fatalError("Toggle has no body") }
}

/// `SwiftUI.TextField`.
public struct TextField: View {
    public init(_ title: String, text: Binding<String>) {}
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {}
    public init(_ title: String, text: Binding<String>, axis: Axis) {}
    public var body: Never { fatalError("TextField has no body") }
}

/// `SwiftUI.SecureField`.
public struct SecureField: View {
    public init(_ title: String, text: Binding<String>) {}
    public var body: Never { fatalError("SecureField has no body") }
}

/// `SwiftUI.Slider`.
public struct Slider: View {
    public init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double? = nil) {}
    public init(value: Binding<Double>, in bounds: ClosedRange<Double>) {}
    /// The slider that reports the start and the end of the drag — the real
    /// API is `init(value:in:onEditingChanged:)`.
    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {}
    public var body: Never { fatalError("Slider has no body") }
}

/// `SwiftUI.Stepper`.
public struct Stepper: View {
    public init(_ title: String, value: Binding<Int>, in bounds: ClosedRange<Int>) {}
    public init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1) {}
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> some View
    ) {}
    /// The real SwiftUI also has a `Strideable` overload (the integer
    /// steppers) — it is needed by the delay picker of the source picker.
    public init<V: Strideable>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> some View
    ) {}
    public var body: Never { fatalError("Stepper has no body") }
}

/// `SwiftUI.Axis`.
public enum Axis: Sendable {
    case horizontal
    case vertical

    /// `SwiftUI.Axis.Set`.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

extension Axis.Set: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Axis...) {
        var value = 0
        for element in elements {
            value |= element == .horizontal ? 1 : 2
        }
        self.init(rawValue: value)
    }
}

/// `SwiftUI.Picker`.
public struct Picker<Selection: Hashable, Content: View>: View {
    public init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {}
    public init(selection: Binding<Selection>, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("Picker has no body") }
}

/// `SwiftUI.Menu`.
public struct Menu<Content: View>: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> some View) {}
    /// The `Menu(_:content:)` form — the title is the label.
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("Menu has no body") }
}

/// `SwiftUI.Label`.
public struct Label: View {
    public init<S: StringProtocol>(_ title: S, systemImage: String) {}
    public init(@ViewBuilder content: () -> some View) {}
    /// The `Label { title } icon: { icon }` form.
    public init(@ViewBuilder title: () -> some View, @ViewBuilder icon: () -> some View) {}
    public var body: Never { fatalError("Label has no body") }
}

/// `SwiftUI.Link`.
public struct Link<Label: View>: View {
    public init(destination: URL, @ViewBuilder label: () -> Label) {}
    public var body: Never { fatalError("Link has no body") }
}

extension Link where Label == Text {
    /// The `Link(_:destination:)` form — the label is a string.
    public init(_ title: String, destination: URL) {}
}

/// `SwiftUI.Divider`.
public struct Divider: View {
    public init() {}
    public var body: Never { fatalError("Divider has no body") }
}

/// `SwiftUI.ProgressView`.
public struct ProgressView: View {
    public init() {}
    public init(_ title: String) {}
    public init<V: BinaryInteger>(value: V?, total: V? = nil) {}
    public var body: Never { fatalError("ProgressView has no body") }
}

/// `SwiftUI.DisclosureGroup`.
public struct DisclosureGroup<Content: View>: View {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("DisclosureGroup has no body") }
}

/// `SwiftUI.EditButton`.
public struct EditButton: View {
    public init() {}
    public var body: Never { fatalError("EditButton has no body") }
}

/// `SwiftUI.ShareLink` is not part of the shim — the port does not use it.

// MARK: - Containers

/// `SwiftUI.VStack`.
public struct VStack<Content: View>: View {
    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("VStack has no body") }
}

/// `SwiftUI.HStack`.
public struct HStack<Content: View>: View {
    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("HStack has no body") }
}

/// `SwiftUI.ZStack`.
public struct ZStack<Content: View>: View {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("ZStack has no body") }
}

/// `SwiftUI.Group`.
public struct Group<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("Group has no body") }
}

/// `SwiftUI.Spacer`.
public struct Spacer: View {
    public init(minLength: Double? = nil) {}
    public var body: Never { fatalError("Spacer has no body") }
}

/// `SwiftUI.List`.
public struct List<RowContent: View>: View {
    public init(@ViewBuilder content: () -> RowContent) {}
    public init<Data: RandomAccessCollection>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) {}
    public init<Data: RandomAccessCollection>(_ data: Data, id: KeyPath<Data.Element, some Hashable>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) {}
    public var body: Never { fatalError("List has no body") }
}

/// `SwiftUI.Section`.
public struct Section<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
    public init(@ViewBuilder header: () -> some View, @ViewBuilder content: () -> Content) {}
    public init(@ViewBuilder header: () -> some View, @ViewBuilder footer: () -> some View, @ViewBuilder content: () -> Content) {}
    /// The `Section { … } header: { … }` form — the header is the LAST
    /// parameter, exactly like the real SwiftUI.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> some View) {}
    public var body: Never { fatalError("Section has no body") }
}

/// `SwiftUI.Form`.
public struct Form<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("Form has no body") }
}

/// `SwiftUI.ScrollViewReader` — the content closure receives the proxy.
public struct ScrollViewReader<Content: View>: View {
    public init(@ViewBuilder content: (ScrollViewProxy) -> Content) {}
    public var body: Never { fatalError("ScrollViewReader has no body") }
}

/// `SwiftUI.ScrollViewProxy`.
public struct ScrollViewProxy {
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {}
}

/// `SwiftUI.ScrollView`.
public struct ScrollView<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public init(_ axes: Axis.Set, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("ScrollView has no body") }
}

/// `SwiftUI.GeometryReader` — the content closure receives the geometry
/// proxy. The shim reports a zero size; it only has to type-check.
public struct GeometryReader<Content: View>: View {
    public init(@ViewBuilder content: (GeometryProxy) -> Content) {}
    public var body: Never { fatalError("GeometryReader has no body") }
}

/// `SwiftUI.GeometryProxy`.
public struct GeometryProxy {
    public var size: CGSize { CGSize(width: 0, height: 0) }
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
}

/// `SwiftUI.LazyVStack`.
public struct LazyVStack<Content: View>: View {
    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("LazyVStack has no body") }
}

/// `SwiftUI.LazyHStack`.
public struct LazyHStack<Content: View>: View {
    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("LazyHStack has no body") }
}

/// `SwiftUI.LazyVGrid`.
public struct LazyVGrid<Content: View>: View {
    public init(columns: [GridItem], spacing: Double? = nil, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("LazyVGrid has no body") }
}

/// `SwiftUI.GridItem`.
public struct GridItem: Sendable {
    public enum Size: Sendable {
        case fixed(Double)
        case flexible(minimum: Double = 10, maximum: Double = 100)
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }
    public init(_ size: Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) {}
}

/// `SwiftUI.ForEach`.
public struct ForEach<Data, ID, Content: View>: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data: RandomAccessCollection, ID: Hashable {}
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data: RandomAccessCollection, Data.Element: Identifiable, ID == Data.Element.ID {}
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) where ID == Int {}
    public var body: Never { fatalError("ForEach has no body") }
}

/// `SwiftUI.NavigationStack`.
public struct NavigationStack<Content: View>: View {
    public init(@ViewBuilder root: () -> Content) {}
    public var body: Never { fatalError("NavigationStack has no body") }
}

/// `SwiftUI.NavigationLink`.
public struct NavigationLink<Label: View, Destination: View>: View {
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {}
    public init<D: Hashable>(_ destination: D, @ViewBuilder label: () -> Label) where Destination == AnyView {}
    public var body: Never { fatalError("NavigationLink has no body") }
}

/// `SwiftUI.NavigationSplitView`.
public struct NavigationSplitView<Sidebar: View, Detail: View>: View {
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {}
    public var body: Never { fatalError("NavigationSplitView has no body") }
}

/// `SwiftUI.TabView`.
///
/// The port always selects a tab with a tag, so the shim only knows the
/// selection based initialiser.
public struct TabView<Selection: Hashable, Content: View>: View {
    public init(selection: Binding<Selection>, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("TabView has no body") }
}

/// `SwiftUI.ToolbarItem`.
///
/// The real SwiftUI type has two initialisers (one taking `content:` and one
/// taking `label:`); the shim keeps only the `content:` one, which is the one
/// the port's views use.
public struct ToolbarItem<Content: View, Placement: ToolbarItemPlacement>: View {
    public init(placement: Placement = .automatic, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError("ToolbarItem has no body") }
}

/// `SwiftUI.TextEditor`.
public struct TextEditor: View {
    public var text: Binding<String>
    public init(text: Binding<String>) { self.text = text }
    public var body: Never { fatalError("TextEditor has no body") }
}

/// `SwiftUI.ToolbarItemPlacement`.
///
/// In SwiftUI this is a *protocol* with a set of static members that are only
/// available on the concrete conforming types, so the shim mirrors that shape
/// (a plain struct with static members would make `.primaryAction` a different
/// type than `.automatic` and break the generic inference of `ToolbarItem`).
public protocol ToolbarItemPlacement {}

public struct ToolbarItemPlacementAutomatic: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementPrimaryAction: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementSecondaryAction: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementTopBarLeading: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementTopBarTrailing: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementBottomBar: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementCancellationAction: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementConfirmationAction: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementDestructiveAction: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementNavigationBarLeading: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementNavigationBarTrailing: ToolbarItemPlacement { public init() {} }
public struct ToolbarItemPlacementPrincipal: ToolbarItemPlacement { public init() {} }

extension ToolbarItemPlacement where Self == ToolbarItemPlacementAutomatic {
    public static var automatic: ToolbarItemPlacementAutomatic { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementPrimaryAction {
    public static var primaryAction: ToolbarItemPlacementPrimaryAction { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementSecondaryAction {
    public static var secondaryAction: ToolbarItemPlacementSecondaryAction { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementTopBarLeading {
    public static var topBarLeading: ToolbarItemPlacementTopBarLeading { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementTopBarTrailing {
    public static var topBarTrailing: ToolbarItemPlacementTopBarTrailing { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementBottomBar {
    public static var bottomBar: ToolbarItemPlacementBottomBar { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementCancellationAction {
    public static var cancellationAction: ToolbarItemPlacementCancellationAction { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementConfirmationAction {
    public static var confirmationAction: ToolbarItemPlacementConfirmationAction { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementDestructiveAction {
    public static var destructiveAction: ToolbarItemPlacementDestructiveAction { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementNavigationBarLeading {
    public static var navigationBarLeading: ToolbarItemPlacementNavigationBarLeading { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementNavigationBarTrailing {
    public static var navigationBarTrailing: ToolbarItemPlacementNavigationBarTrailing { .init() }
}
extension ToolbarItemPlacement where Self == ToolbarItemPlacementPrincipal {
    public static var principal: ToolbarItemPlacementPrincipal { .init() }
}

/// `SwiftUI.ToolbarContent`.
public protocol ToolbarContent {}
extension ToolbarItem: ToolbarContent {}
