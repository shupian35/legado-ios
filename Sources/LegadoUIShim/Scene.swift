//
//  Scene.swift
//  LegadoUIShim
//
//  The scene/app part of the SwiftUI stand-in.
//
//  The `@main` entry point of the port only exists on Apple platforms, but the
//  shared UI layer must compile on Linux as well, so the few scene types the
//  app uses are mirrored here.
//
//  NOTE: `Never` is deliberately NOT made to conform to `Scene` — `Never` is
//  already the `View` body of the shim, and a second `body` witness would be an
//  invalid redeclaration.
//
//  See `View.swift` for the rationale of the shim.
//

import Foundation

// MARK: - Scene

/// `SwiftUI.Scene`.
@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
}

/// `SwiftUI.App`.
///
/// The real SwiftUI `App` protocol has no `main()` — the compiler synthesises it
/// for an `@main` type. The shim declares it (with an empty default) so the
/// same `@main` entry point compiles on Linux as well.
@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    init()
    @SceneBuilder var body: Body { get }
    static func main()
}

/// The hook the Linux build uses instead of the SwiftUI run loop.
///
/// SwiftUI has no equivalent on Linux, so the shim's `App.main()` creates the
/// app (which runs its `init()`) and then calls the closure the app
/// installed. The iOS/macOS build never touches this type — there the real
/// SwiftUI drives the scene.
public final class AppRuntime {
    public static let shared = AppRuntime()

    /// The work the process has to do instead of running a UI loop.
    public var main: (() -> Void)?

    private init() {}
}

extension App {
    public static func main() {
        _ = Self()
        AppRuntime.shared.main?()
    }
}

/// `SwiftUI.WindowGroup`.
public struct WindowGroup<Content: View>: Scene {
    public init(@ViewBuilder content: () -> Content) {}
    public init(id: String, @ViewBuilder content: () -> Content) {}
    public var body: EmptyScene { EmptyScene() }
}

/// `SwiftUI.Window`.
public struct Window<Content: View>: Scene {
    public init(id: String, @ViewBuilder content: () -> Content) {}
    public var body: EmptyScene { EmptyScene() }
}

/// `SwiftUI.Settings`.
public struct Settings<Content: View>: Scene {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: EmptyScene { EmptyScene() }
}

/// `SwiftUI.SceneBuilder`.
@resultBuilder
@MainActor
public enum SceneBuilder {
    public static func buildBlock() -> EmptyScene { EmptyScene() }
    public static func buildBlock<S: Scene>(_ scene: S) -> S { scene }
    public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> TupleScene<(S0, S1)> { TupleScene((s0, s1)) }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene>(_ s0: S0, _ s1: S1, _ s2: S2) -> TupleScene<(S0, S1, S2)> { TupleScene((s0, s1, s2)) }
    public static func buildIf<S: Scene>(_ scene: S?) -> S? { scene }
    public static func buildOptional<S: Scene>(_ scene: S?) -> S? { scene }
    public static func buildEither<T: Scene, F: Scene>(first: T) -> ConditionalScene<T, F> { ConditionalScene(first: first, second: nil) }
    public static func buildEither<T: Scene, F: Scene>(second: F) -> ConditionalScene<T, F> { ConditionalScene(first: nil, second: second) }
}

/// The empty scene of the shim.
public struct EmptyScene: Scene {
    public init() {}
    public var body: EmptyScene { EmptyScene() }
}

/// A tuple of scenes.
public struct TupleScene<T>: Scene {
    public let value: T
    public init(_ value: T) { self.value = value }
    public var body: EmptyScene { EmptyScene() }
}

/// The result of an `if`/`else` inside a `SceneBuilder`.
public struct ConditionalScene<TrueScene: Scene, FalseScene: Scene>: Scene {
    let first: TrueScene?
    let second: FalseScene?
    public var body: EmptyScene { EmptyScene() }
}

// MARK: - Scene phase

/// `SwiftUI.ScenePhase`.
public enum ScenePhase: Hashable, Sendable {
    case background
    case inactive
    case active
}
