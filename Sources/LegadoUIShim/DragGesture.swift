import Foundation

/// `SwiftUI.DragGesture` — the drag recogniser of the reader.
///
/// The shim only has to type-check: the value carries the same fields as the
/// real gesture so the shared view code can be written once.
public struct DragGesture: Equatable {

    /// The minimum distance before the gesture starts.
    public var minimumDistance: Double

    public init(minimumDistance: Double = 10) {
        self.minimumDistance = minimumDistance
    }

    /// The state of the gesture.
    public struct Value: Equatable {
        public var time: TimeInterval
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize
        public var predictedEndTranslation: CGSize
        public var velocity: CGSize

        public init(
            time: TimeInterval = 0,
            location: CGPoint = .zero,
            startLocation: CGPoint = .zero,
            translation: CGSize = .zero,
            predictedEndTranslation: CGSize = .zero,
            velocity: CGSize = .zero
        ) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.translation = translation
            self.predictedEndTranslation = predictedEndTranslation
            self.velocity = velocity
        }
    }

    /// The action run while the gesture changes.
    @MainActor
    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGestureModifier {
        DragGestureModifier()
    }

    /// The action run when the gesture ends.
    @MainActor
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGestureModifier {
        DragGestureModifier()
    }
}

/// `SwiftUI.Gesture` — the shim only needs the marker so the shared code can
/// spell `some Gesture` (the real `DragGesture().onChanged { }` is a
/// `Gesture`, the shim's `DragGestureModifier` is a `View`).
public protocol Gesture {}

/// The result of `onChanged`/`onEnded` — in SwiftUI the returned value can be
/// chained (`DragGesture().onChanged { }.onEnded { }`), so the shim offers
/// both methods again.
public struct DragGestureModifier: View, Gesture {
    public init() {}
    public var body: Never { fatalError("LegadoUIShim never renders") }
    public func onChanged(_ action: @escaping (DragGesture.Value) -> Void) -> DragGestureModifier { self }
    public func onEnded(_ action: @escaping (DragGesture.Value) -> Void) -> DragGestureModifier { self }
}

/// `SwiftUI.MagnificationGesture` — the pinch of the manga reader.
///
/// The shim only has to type-check: the value carries the same fields as the
/// real gesture so the shared view code can be written once.
public struct MagnificationGesture: Equatable {

    /// The minimum scale change before the gesture starts.
    public var minimumScaleDelta: Double

    public init(minimumScaleDelta: Double = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    /// The state of the gesture. The real SwiftUI spells it as `CGFloat`
    /// (the scale factor), so one code path works on both platforms.
    public typealias Value = Double

    /// The action run while the gesture changes.
    @MainActor
    public func onChanged(_ action: @escaping (Value) -> Void) -> MagnificationGestureModifier {
        MagnificationGestureModifier()
    }

    /// The action run when the gesture ends.
    @MainActor
    public func onEnded(_ action: @escaping (Value) -> Void) -> MagnificationGestureModifier {
        MagnificationGestureModifier()
    }
}

/// The result of `onChanged`/`onEnded` — in SwiftUI the returned value can be
/// chained, so the shim offers both methods again.
public struct MagnificationGestureModifier: View, Gesture {
    public init() {}
    public var body: Never { fatalError("LegadoUIShim never renders") }
    public func onChanged(_ action: @escaping (MagnificationGesture.Value) -> Void) -> MagnificationGestureModifier { self }
    public func onEnded(_ action: @escaping (MagnificationGesture.Value) -> Void) -> MagnificationGestureModifier { self }
}

/// `SwiftUI.withAnimation` — runs a closure inside an animation transaction.
public func withAnimation<T>(_ animation: Animation? = nil, _ body: () throws -> T) rethrows -> T {
    try body()
}

/// `SwiftUI.withTransaction` — runs a closure inside a transaction.
public func withTransaction<T>(_ transaction: Transaction = Transaction(), _ body: () throws -> T) rethrows -> T {
    try body()
}
