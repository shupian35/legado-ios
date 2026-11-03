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
    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGestureModifier {
        DragGestureModifier()
    }

    /// The action run when the gesture ends.
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGestureModifier {
        DragGestureModifier()
    }
}

/// The result of `onChanged`/`onEnded` — in SwiftUI the returned value can be
/// chained (`DragGesture().onChanged { }.onEnded { }`), so the shim offers
/// both methods again.
public struct DragGestureModifier: View {
    public init() {}
    public var body: Never { fatalError("LegadoUIShim never renders") }
    public func onChanged(_ action: @escaping (DragGesture.Value) -> Void) -> DragGestureModifier { self }
    public func onEnded(_ action: @escaping (DragGesture.Value) -> Void) -> DragGestureModifier { self }
}

/// `SwiftUI.withAnimation` — runs a closure inside an animation transaction.
public func withAnimation<T>(_ animation: Animation? = nil, _ body: () throws -> T) rethrows -> T {
    try body()
}

/// `SwiftUI.withAnimation` with an explicit duration.
public func withAnimation<T>(_ animation: Animation? = nil, body: () throws -> T) rethrows -> T {
    try body()
}

/// `SwiftUI.withTransaction` — runs a closure inside a transaction.
public func withTransaction<T>(_ transaction: Transaction = Transaction(), _ body: () throws -> T) rethrows -> T {
    try body()
}
