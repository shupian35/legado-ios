//
//  State.swift
//  LegadoUIShim
//
//  The state management of SwiftUI — `SwiftUI.State`, `SwiftUI.Binding`,
//  `SwiftUI.ObservedObject`, `SwiftUI.StateObject`, `SwiftUI.Environment`,
//  `SwiftUI.EnvironmentObject` — plus the Combine pieces
//  (`ObservableObject`, `Published`) that do not exist on Linux.
//
//  See `View.swift` for the rationale of the shim.
//

import Foundation

// MARK: - Observable objects

/// `Combine.ObservableObjectPublisher`.
public final class ObservableObjectPublisher {
    private var observers: [UUID: () -> Void] = [:]
    public init() {}
    public func send() {
        for observer in observers.values { observer() }
    }
    public func receive<Output>(subscriber: (Output) -> Void) {}
}

/// `Combine.ObservableObject`.
public protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}

extension ObservableObject {
    public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}

/// `Combine.Published`.
@propertyWrapper
public struct Published<Value> {
    private final class Storage {
        var value: Value
        let subject = ObservableObjectPublisher()
        init(_ value: Value) { self.value = value }
    }
    private let storage: Storage

    public init(wrappedValue: Value) { storage = Storage(wrappedValue) }

    public var wrappedValue: Value {
        get { storage.value }
        set {
            storage.subject.send()
            storage.value = newValue
        }
    }

    public var projectedValue: ObservableObjectPublisher { storage.subject }
}

// MARK: - Bindings

/// `SwiftUI.Binding`.
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getter = get
        self.setter = set
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    public var projectedValue: Binding<Value> { self }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// The dynamic member lookup that turns `$model.property` into a binding
    /// of the property — the same projection the real SwiftUI offers.
    ///
    /// A `WritableKeyPath` (not `ReferenceWritableKeyPath`) is used because
    /// the bound value is usually a struct; the write is copied back through
    /// the binding so a `@State` keeps the change.
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        // The explicit `Binding<Subject>` matters: without it the compiler
        // infers the generic from the closures and falls back to the outer
        // `Value` (the standard library's key-path subscript also uses the
        // name `Value`).
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { subject in
                var copy = self.wrappedValue
                copy[keyPath: keyPath] = subject
                self.wrappedValue = copy
            }
        )
    }
}

/// `SwiftUI.State`.
@propertyWrapper
public struct State<Value> {
    private final class Storage {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let storage: Storage

    public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    public init(initialValue: Value) { storage = Storage(initialValue) }

    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { storage.value }, set: { storage.value = $0 })
    }
}

/// `SwiftUI.ObservedObject`.
@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(wrappedValue) }
}

extension ObservedObject {
    /// `SwiftUI.ObservedObject.Wrapper`.
    ///
    /// `@dynamicMemberLookup` is REQUIRED: without it the compiler resolves
    /// `$model.property` against the *wrapped value* instead of the
    /// `dynamicMember` subscript and reports
    /// "referencing property 'x' requires wrapped value of type 'T'".
    @dynamicMemberLookup
    public struct Wrapper {
        public var wrappedValue: ObjectType
        init(_ value: ObjectType) { wrappedValue = value }

        /// The dynamic member lookup that turns `$model.property` into a
        /// `Binding` — the same projection the real SwiftUI offers.
        public subscript<Subject>(
            dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>
        ) -> Binding<Subject> {
            Binding(
                get: { wrappedValue[keyPath: keyPath] },
                set: { wrappedValue[keyPath: keyPath] = $0 }
            )
        }
    }
}

/// `SwiftUI.StateObject`.
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    private let object: ObjectType
    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) { object = wrappedValue() }
    public var wrappedValue: ObjectType { object }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object) }
}

/// `SwiftUI.Environment`.
@propertyWrapper
public struct Environment<Value> {
    private let keyPath: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    public var wrappedValue: Value { EnvironmentBox.shared.value(for: keyPath) }
}

/// `SwiftUI.EnvironmentObject`.
@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType {
        get { fatalError("EnvironmentObject is not available in the shim") }
        nonmutating set {}
    }
    public init() {}
}

/// The storage of the environment values of the shim.
public final class EnvironmentBox {
    public static let shared = EnvironmentBox()
    private var values: [AnyKeyPath: Any] = [:]

    public init() {}

    func value<T>(for keyPath: KeyPath<EnvironmentValues, T>) -> T {
        if let stored = values[keyPath as AnyKeyPath] as? T { return stored }
        return EnvironmentValues.defaultValue(for: keyPath)
    }

    func set<T>(_ value: T, for keyPath: KeyPath<EnvironmentValues, T>) {
        values[keyPath as AnyKeyPath] = value
    }
}

/// `SwiftUI.EnvironmentValues`.
public struct EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { EnvironmentBox.shared.value(for: \.colorScheme) }
        set { EnvironmentBox.shared.set(newValue, for: \.colorScheme) }
    }
    public var dismiss: DismissAction {
        get { EnvironmentBox.shared.value(for: \.dismiss) }
        set { EnvironmentBox.shared.set(newValue, for: \.dismiss) }
    }
    public var isLanding: Bool {
        get { EnvironmentBox.shared.value(for: \.isLanding) }
        set { EnvironmentBox.shared.set(newValue, for: \.isLanding) }
    }
    public var openURL: OpenURLAction {
        get { EnvironmentBox.shared.value(for: \.openURL) }
        set { EnvironmentBox.shared.set(newValue, for: \.openURL) }
    }

    public subscript<T>(keyPath: KeyPath<EnvironmentValues, T>) -> T {
        get { EnvironmentBox.shared.value(for: keyPath) }
        set { EnvironmentBox.shared.set(newValue, for: keyPath) }
    }

    static func defaultValue<T>(for keyPath: KeyPath<EnvironmentValues, T>) -> T {
        let key = keyPath as AnyKeyPath
        if key == (\EnvironmentValues.colorScheme as AnyKeyPath) {
            return ColorScheme.light as! T
        }
        if key == (\EnvironmentValues.dismiss as AnyKeyPath) {
            return DismissAction() as! T
        }
        if key == (\EnvironmentValues.isLanding as AnyKeyPath) {
            return false as! T
        }
        if key == (\EnvironmentValues.openURL as AnyKeyPath) {
            return OpenURLAction() as! T
        }
        fatalError("Unknown environment key \(key)")
    }
}

/// `SwiftUI.DismissAction`.
public struct DismissAction {
    public init() {}
    public func callAsFunction() {}
}

/// `SwiftUI.OpenURLAction`.
public struct OpenURLAction {
    public init() {}
    public func callAsFunction(_ url: URL) {}
}

/// `SwiftUI.ColorScheme`.
public enum ColorScheme: String, Sendable {
    case light
    case dark
}
