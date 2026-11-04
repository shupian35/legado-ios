//
//  Modifiers.swift
//  LegadoUIShim
//
//  The view modifiers of SwiftUI that the port uses. Every modifier returns
//  `some View` exactly like the real ones, so the call sites of the shared UI
//  layer are source compatible with the real SwiftUI.
//
//  See `View.swift` for the rationale of the shim.
//

import Foundation

extension View {

    // MARK: - Layout

    public func padding(_ length: Double) -> some View { ModifiedView(self) }
    public func padding(_ insets: EdgeInsets) -> some View { ModifiedView(self) }
    public func padding(_ edges: Edge.Set, _ length: Double? = nil) -> some View { ModifiedView(self) }
    public func padding() -> some View { ModifiedView(self) }
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> some View { ModifiedView(self) }
    public func frame(minWidth: Double? = nil, idealWidth: Double? = nil, maxWidth: Double? = nil, minHeight: Double? = nil, idealHeight: Double? = nil, maxHeight: Double? = nil, alignment: Alignment = .center) -> some View { ModifiedView(self) }
    public func fixedSize(horizontal: Bool = false, vertical: Bool = false) -> some View { ModifiedView(self) }
    public func layoutPriority(_ value: Double) -> some View { ModifiedView(self) }
    public func flexedSpace() -> some View { ModifiedView(self) }
    public func aspectRatio(_ ratio: Double? = nil, contentMode: ContentMode) -> some View { ModifiedView(self) }
    public func scaledToFit() -> some View { ModifiedView(self) }
    public func scaledToFill() -> some View { ModifiedView(self) }
    public func alignmentGuide(_ guide: HorizontalAlignment, computeValue: @escaping (Double) -> Double) -> some View { ModifiedView(self) }
    public func alignmentGuide(_ guide: VerticalAlignment, computeValue: @escaping (Double) -> Double) -> some View { ModifiedView(self) }
    public func listRowInsets(_ insets: EdgeInsets) -> some View { ModifiedView(self) }
    public func listRowSeparator(_ visibility: Visibility = .automatic) -> some View { ModifiedView(self) }
    public func listRowBackground<V: View>(_ background: V) -> some View { ModifiedView(self) }
    public func safeAreaInset<V: View>(edge: Edge.Set, alignment: Alignment = .center, spacing: Double? = nil, content: @escaping () -> V) -> some View { ModifiedView(self) }
    public func ignoresSafeArea(_ edges: Edge.Set = .all) -> some View { ModifiedView(self) }
    public func containerRelativeFrame(_ axes: Axis.Set = .horizontal) -> some View { ModifiedView(self) }

    // MARK: - Appearance

    public func font(_ font: Font?) -> some View { ModifiedView(self) }
    public func fontWeight(_ weight: Font.Weight?) -> some View { ModifiedView(self) }
    public func bold() -> some View { ModifiedView(self) }
    public func italic() -> some View { ModifiedView(self) }
    public func underline(_ isActive: Bool = true, pattern: UnderlinePattern = .solid) -> some View { ModifiedView(self) }
    public func strikethrough(_ isActive: Bool = true, pattern: UnderlinePattern = .solid) -> some View { ModifiedView(self) }
    public func foregroundColor(_ color: Color?) -> some View { ModifiedView(self) }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func background<V: View>(_ background: V) -> some View { ModifiedView(self) }
    public func background<V: View>(_ background: V, alignment: Alignment = .center) -> some View { ModifiedView(self) }
    public func background(_ color: Color) -> some View { ModifiedView(self) }
    public func overlay<V: View>(_ overlay: V) -> some View { ModifiedView(self) }
    public func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> some View { ModifiedView(self) }
    /// The real SwiftUI also has the builder form
    /// (`overlay(alignment:content:)`) — the shim mirrors it.
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { ModifiedView(self) }
    public func opacity(_ opacity: Double) -> some View { ModifiedView(self) }
    public func hidden() -> some View { ModifiedView(self) }
    public func cornerRadius(_ radius: Double) -> some View { ModifiedView(self) }
    public func clipped() -> some View { ModifiedView(self) }
    public func border<S: ShapeStyle>(_ style: S, width: Double = 1) -> some View { ModifiedView(self) }
    public func border(_ color: Color, width: Double = 1) -> some View { ModifiedView(self) }
    public func clipShape<S: Shape>(_ shape: S) -> some View { ModifiedView(self) }
    public func shadow(color: Color = .black, radius: Double, x: Double = 0, y: Double = 0) -> some View { ModifiedView(self) }
    public func tint(_ color: Color?) -> some View { ModifiedView(self) }
    public func accentColor(_ color: Color?) -> some View { ModifiedView(self) }
    public func redacted(reason: RedactionReasons = .placeholder) -> some View { ModifiedView(self) }
    public func blur(radius: Double) -> some View { ModifiedView(self) }
    public func saturation(_ amount: Double) -> some View { ModifiedView(self) }
    /// `SwiftUI.grayscale` — the manga reader's grey mode.
    public func grayscale(_ amount: Double) -> some View { ModifiedView(self) }
    /// `SwiftUI.colorMultiply` — the manga reader's colour filter.
    public func colorMultiply(_ color: Color) -> some View { ModifiedView(self) }
    /// `SwiftUI.contrast` — the manga reader's e-ink mode.
    public func contrast(_ amount: Double) -> some View { ModifiedView(self) }
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> some View { ModifiedView(self) }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { ModifiedView(self) }
    public func offset(x: Double = 0, y: Double = 0) -> some View { ModifiedView(self) }
    public func rotation3DEffect(_ angle: Angle, axis: (x: Double, y: Double, z: Double)) -> some View { ModifiedView(self) }
    public func lineLimit(_ number: Int?) -> some View { ModifiedView(self) }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { ModifiedView(self) }
    public func minimumScaleFactor(_ factor: Double) -> some View { ModifiedView(self) }
    public func textCase(_ textCase: TextCase?) -> some View { ModifiedView(self) }
    public func kerning(_ kerning: Double) -> some View { ModifiedView(self) }
    public func tracking(_ tracking: Double) -> some View { ModifiedView(self) }
    public func baselineOffset(_ offset: Double) -> some View { ModifiedView(self) }
    public func allowsHitTesting(_ allows: Bool) -> some View { ModifiedView(self) }
    public func contentShape<S: Shape>(_ shape: S) -> some View { ModifiedView(self) }
    public func labelsHidden() -> some View { ModifiedView(self) }
    public func onDelete(perform action: @escaping (IndexSet) -> Void) -> some View { ModifiedView(self) }
    /// `onMove(perform:)` — the destination is the index the row is moved to,
    /// the way the real `SwiftUI` reports it (`(IndexSet, Int) -> Void`).
    public func onMove(perform action: @escaping (IndexSet, Int) -> Void) -> some View { ModifiedView(self) }
    public func onInsert(perform action: @escaping (IndexSet) -> Void) -> some View { ModifiedView(self) }

    // MARK: - Interaction

    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { ModifiedView(self) }
    public func onSubmit(_ action: @escaping () -> Void) -> some View { ModifiedView(self) }
    public func onSubmit(of triggers: SubmitLabel, _ action: @escaping () -> Void) -> some View { ModifiedView(self) }
    /// The file importer — the real SwiftUI has two overloads: the single
    /// file one returns `Result<URL, Error>` and the multiple selection one
    /// returns `Result<[URL], Error>`.
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View { ModifiedView(self) }
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View { ModifiedView(self) }
    public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .global, perform action: @escaping (CGPoint) -> Void) -> some View { ModifiedView(self) }
    /// The long press — the real SwiftUI spells it `onLongPressGesture`, but
    /// `onLongPress` is a common shortcut for it.
    public func onLongPress(minimumDuration: Double = 0.5, perform action: @escaping () -> Void) -> some View { ModifiedView(self) }
    public func onLongPressGesture(minimumDuration: Double = 0.5, perform action: @escaping () -> Void) -> some View { ModifiedView(self) }
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: Double = 10, pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View { ModifiedView(self) }
    public func simultaneousGesture<T: View>(_ gesture: T) -> some View { ModifiedView(self) }
    public func gesture<T>(_ gesture: T) -> some View { ModifiedView(self) }
    public func highPriorityGesture<T: View>(_ gesture: T) -> some View { ModifiedView(self) }
    public func disabled(_ disabled: Bool) -> some View { ModifiedView(self) }
    public func help(_ text: String) -> some View { ModifiedView(self) }
    public func accessibilityLabel(_ label: String) -> some View { ModifiedView(self) }
    public func accessibilityIdentifier(_ identifier: String) -> some View { ModifiedView(self) }
    /// The context menu of a view — the real SwiftUI offers it since iOS 13.
    public func contextMenu<Items: View>(@ViewBuilder menuItems: () -> Items) -> some View { ModifiedView(self) }

    // MARK: - Life cycle

    // The life cycle closures run on the main actor — on Apple platforms the
    // whole `View` protocol is main actor isolated, so the closures inherit
    // that isolation.
    public func onAppear(perform action: (@MainActor () -> Void)? = nil) -> some View { ModifiedView(self) }
    public func onDisappear(perform action: (@MainActor () -> Void)? = nil) -> some View { ModifiedView(self) }
    public func onOpenURL(perform action: @escaping (URL) -> Void) -> some View { ModifiedView(self) }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View { ModifiedView(self) }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V) -> Void) -> some View { ModifiedView(self) }
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View { ModifiedView(self) }
    public func task<V: Equatable>(id: V, priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View { ModifiedView(self) }
    public func refreshable(_ action: @escaping @Sendable () async -> Void) -> some View { ModifiedView(self) }
    public func animation(_ animation: Animation?, value: some Equatable) -> some View { ModifiedView(self) }
    public func animation(_ animation: Animation? = nil) -> some View { ModifiedView(self) }
    public func transaction(_ transform: (inout Transaction) -> Void) -> some View { ModifiedView(self) }
    public func transition(_ transition: AnyTransition) -> some View { ModifiedView(self) }

    // MARK: - Navigation

    public func navigationTitle(_ title: String) -> some View { ModifiedView(self) }
    public func navigationTitle(_ title: Text) -> some View { ModifiedView(self) }
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.DisplayMode) -> some View { ModifiedView(self) }
    public func navigationDestination<V: Hashable>(for value: V, @ViewBuilder destination: @escaping (V) -> some View) -> some View { ModifiedView(self) }
    public func navigationBarHidden(_ hidden: Bool) -> some View { ModifiedView(self) }
    public func toolbar(@ToolbarContentBuilder content: () -> some ToolbarContent) -> some View { ModifiedView(self) }
    public func toolbar(id: String, @ToolbarContentBuilder content: () -> some ToolbarContent) -> some View { ModifiedView(self) }
    public func tabItem<V: View>(@ViewBuilder content: () -> V) -> some View { ModifiedView(self) }
    public func badge(_ count: Int) -> some View { ModifiedView(self) }
    public func badge(_ label: Text?) -> some View { ModifiedView(self) }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: String? = nil) -> some View { ModifiedView(self) }
    public func searchable<V: Hashable>(selection: Binding<V?>, placement: SearchFieldPlacement = .automatic, prompt: String? = nil) -> some View { ModifiedView(self) }

    // MARK: - Presentation

    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { ModifiedView(self) }
    public func sheet<V: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> V) -> some View { ModifiedView(self) }
    public func sheet<Item, V: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> V) -> some View { ModifiedView(self) }
    public func popover<V: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rectangle, arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> V) -> some View { ModifiedView(self) }
    public func alert<Item, A: View, M: View>(_ title: String, isPresented: Binding<Bool>, presenting: Item? = nil, @ViewBuilder actions: @escaping (Item) -> A, @ViewBuilder message: @escaping (Item) -> M) -> some View { ModifiedView(self) }
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View { ModifiedView(self) }
    /// The alert without a message — the real SwiftUI allows it.
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View { ModifiedView(self) }
    public func confirmationDialog<Item, A: View, M: View>(_ title: String, isPresented: Binding<Bool>, presenting: Item? = nil, @ViewBuilder actions: @escaping (Item) -> A, @ViewBuilder message: @escaping (Item) -> M) -> some View { ModifiedView(self) }
    public func confirmationDialog<A: View, M: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View { ModifiedView(self) }
    /// The confirmation dialog without a message — the real SwiftUI allows it.
    public func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> A) -> some View { ModifiedView(self) }

    // MARK: - Lists and forms

    public func listStyle<S: ListStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View { ModifiedView(self) }
    public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { ModifiedView(self) }
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View { ModifiedView(self) }
    public func keyboardType(_ type: KeyboardType) -> some View { ModifiedView(self) }
    public func submitLabel(_ label: SubmitLabel) -> some View { ModifiedView(self) }
    public func tag<V: Hashable>(_ tag: V) -> some View { ModifiedView(self) }
    public func id<V: Hashable>(_ id: V) -> some View { ModifiedView(self) }

    // MARK: - Environment

    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View { ModifiedView(self) }
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View { ModifiedView(self) }
    public func environment<T: ObservableObject>(_ object: T) -> some View { ModifiedView(self) }
}

/// `SwiftUI.UnderlinePattern`.
public enum UnderlinePattern: Sendable {
    case solid
    case double
    case dash
    case dot
}

/// `SwiftUI.TextAlignment`.
public enum TextAlignment: Sendable {
    case leading, center, trailing
}

/// `SwiftUI.TextCase`.
public enum TextCase: Sendable {
    case uppercased, lowercase, capitalized
}

/// `SwiftUI.UnitPoint`.
public struct UnitPoint: Hashable, Sendable {
    public static let leading = UnitPoint()
    public static let trailing = UnitPoint()
    public static let top = UnitPoint()
    public static let bottom = UnitPoint()
    public static let center = UnitPoint()
    public init() {}
}

/// `SwiftUI.Visibility`.
public enum Visibility: Hashable, Sendable {
    case visible, hidden, automatic
}

/// `SwiftUI.CoordinateSpace`.
public struct CoordinateSpace: Hashable, Sendable {
    public static let global = CoordinateSpace()
    /// The local coordinate space of the view — `SwiftUI.CoordinateSpace.local`.
    public static let local = CoordinateSpace()
    public static func named(_ name: String) -> CoordinateSpace { CoordinateSpace() }
    public init() {}
}

/// `SwiftUI.Angle`.
public struct Angle: Hashable, Sendable {
    public let radians: Double
    public let degrees: Double
    public init(radians: Double) { self.radians = radians; degrees = radians * 180 / .pi }
    public init(degrees: Double) { self.degrees = degrees; radians = degrees * .pi / 180 }
    public static let zero = Angle(radians: 0)
    /// `SwiftUI.Angle.degrees(_:)` — the real API is a static factory, the
    /// instance property above is the stored value.
    public static func degrees(_ value: Double) -> Angle { Angle(degrees: value) }
    public static func radians(_ value: Double) -> Angle { Angle(radians: value) }
}

/// `SwiftUI.AnyTransition`.
public struct AnyTransition: Hashable, Sendable {
    public static let identity = AnyTransition()
    public static let opacity = AnyTransition()
    public static let scale = AnyTransition()
    public static let move = AnyTransition()
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public static func combined(with other: AnyTransition) -> AnyTransition { AnyTransition() }
    public init() {}
}

/// `SwiftUI.TaskPriority` is the Swift concurrency type — reused.

/// `SwiftUI.PopoverAttachmentAnchor`.
public struct PopoverAttachmentAnchor: Hashable, Sendable {
    public static let rectangle = PopoverAttachmentAnchor()
    public static let sourceRect = PopoverAttachmentAnchor()
    public init() {}
}

/// `SwiftUI.SearchFieldPlacement`.
public struct SearchFieldPlacement: Hashable, Sendable {
    public static let automatic = SearchFieldPlacement()
    public static let navigationBarDrawer = SearchFieldPlacement()
    public init() {}
}

/// `SwiftUI.TextInputAutocapitalization`.
public struct TextInputAutocapitalization: Hashable, Sendable {
    public static let never = TextInputAutocapitalization()
    public static let words = TextInputAutocapitalization()
    public static let sentences = TextInputAutocapitalization()
    public static let characters = TextInputAutocapitalization()
    public init() {}
}

/// `SwiftUI.KeyboardType`.
public struct KeyboardType: Hashable, Sendable {
    public static let `default` = KeyboardType()
    public static let numberPad = KeyboardType()
    public static let decimalPad = KeyboardType()
    public static let webSearch = KeyboardType()
    public init() {}
}

/// `SwiftUI.SubmitLabel`.
public struct SubmitLabel: Hashable, Sendable {
    public static let done = SubmitLabel()
    public static let go = SubmitLabel()
    public static let search = SubmitLabel()
    public static let send = SubmitLabel()
    public init() {}
}

// MARK: - Styles

/// `SwiftUI.ListStyle`.
public protocol ListStyle {}
public struct PlainListStyle: ListStyle { public init() {} }
public struct InsetGroupedListStyle: ListStyle { public init() {} }
public struct GroupedListStyle: ListStyle { public init() {} }
public struct SidebarListStyle: ListStyle { public init() {} }

/// `SwiftUI.PickerStyle`.
public protocol PickerStyle {}
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
public struct MenuPickerStyle: PickerStyle { public init() {} }
public struct WheelPickerStyle: PickerStyle { public init() {} }
public struct InlinePickerStyle: PickerStyle { public init() {} }

/// The static members of the picker styles — the real SwiftUI offers them
/// since iOS 14 (`.pickerStyle(.segmented)`).
public extension PickerStyle {
    static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
    static var menu: MenuPickerStyle { MenuPickerStyle() }
    static var wheel: WheelPickerStyle { WheelPickerStyle() }
    static var inline: InlinePickerStyle { InlinePickerStyle() }
}

/// `SwiftUI.TextFieldStyle`.
public protocol TextFieldStyle {}
public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {} }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {} }
public struct DefaultTextFieldStyle: TextFieldStyle { public init() {} }
public struct SquareBorderTextFieldStyle: TextFieldStyle { public init() {} }

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var `default`: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}


/// `SwiftUI.ButtonStyle`.
public protocol ButtonStyle {}
public struct DefaultButtonStyle: ButtonStyle { public init() {} }
public struct PlainButtonStyle: ButtonStyle { public init() {} }
public struct BorderlessButtonStyle: ButtonStyle { public init() {} }
public struct BorderedButtonStyle: ButtonStyle { public init() {} }
public struct BorderedProminentButtonStyle: ButtonStyle { public init() {} }

extension ButtonStyle where Self == DefaultButtonStyle {
    public static var `default`: DefaultButtonStyle { DefaultButtonStyle() }
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}
extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}
extension ButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension ButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension ButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}

/// `SwiftUI.LabelStyle`.
public protocol LabelStyle {}
public struct DefaultLabelStyle: LabelStyle { public init() {} }
public struct TitleAndIconLabelStyle: LabelStyle { public init() {} }

/// `SwiftUI.ShapeStyle` — the shim only needs the protocol.
public protocol ShapeStyle {}

// MARK: - Result builders

/// `SwiftUI.ToolbarContentBuilder`.
@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildBlock() -> EmptyToolbarContent { EmptyToolbarContent() }
    public static func buildBlock<C: ToolbarContent>(_ content: C) -> C { content }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(_ c0: C0, _ c1: C1) -> TupleToolbarContent<(C0, C1)> { TupleToolbarContent((c0, c1)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleToolbarContent<(C0, C1, C2)> { TupleToolbarContent((c0, c1, c2)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleToolbarContent<(C0, C1, C2, C3)> { TupleToolbarContent((c0, c1, c2, c3)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleToolbarContent<(C0, C1, C2, C3, C4)> { TupleToolbarContent((c0, c1, c2, c3, c4)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5)> { TupleToolbarContent((c0, c1, c2, c3, c4, c5)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6)> { TupleToolbarContent((c0, c1, c2, c3, c4, c5, c6)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7)> { TupleToolbarContent((c0, c1, c2, c3, c4, c5, c6, c7)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { TupleToolbarContent((c0, c1, c2, c3, c4, c5, c6, c7, c8)) }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent, C9: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { TupleToolbarContent((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) }
}

/// The empty toolbar content of the shim.
public struct EmptyToolbarContent: ToolbarContent {
    public init() {}
}

/// A tuple of toolbar items.
public struct TupleToolbarContent<T>: ToolbarContent {
    public let value: T
    public init(_ value: T) { self.value = value }
}
