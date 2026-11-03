//
//  Representables.swift
//  LegadoUIShim
//
//  The two SwiftUI protocols that wrap a UIKit view.
//
//  `UIViewRepresentable` and `UIViewControllerRepresentable` only exist on
//  Apple platforms. The port uses them for the in-app browser (`WKWebView`),
//  the QR scanner preview, the share sheet and the status-bar host, so the
//  shim needs them to type-check those files on Linux.
//
//  The shapes mirror the real SwiftUI protocols:
//
//  * `associatedtype UIViewType` / `associatedtype UIViewControllerType`;
//  * `associatedtype Coordinator = Void` with the default `makeCoordinator()`;
//  * `typealias Context = UIViewRepresentableContext<Self>`;
//  * `makeUIView(context:)` / `updateUIView(_:context:)` and
//    `makeUIViewController(context:)` / `updateUIViewController(_:context:)`.
//
//  The shim drops the `UIViewType: UIView` / `UIViewControllerType:
//  UIViewController` constraints, because UIKit does not exist on Linux.
//
//  Upstream reference: none — this file has no Android counterpart.
//

import Foundation

// MARK: - The view representable

/// `SwiftUI.UIViewRepresentable`.
public protocol UIViewRepresentable: View where Body == Never {

    /// The UIKit view the representable manages.
    associatedtype UIViewType: AnyObject

    /// The coordinator — `Void` when the representable needs none.
    associatedtype Coordinator = Void

    /// The context handed to the update methods.
    typealias Context = UIViewRepresentableContext<Self>

    /// Creates the coordinator.
    func makeCoordinator() -> Coordinator

    /// Creates the UIKit view.
    func makeUIView(context: Context) -> UIViewType

    /// Updates the UIKit view.
    func updateUIView(_ uiView: UIViewType, context: Context)
}

public extension UIViewRepresentable where Coordinator == Void {
    func makeCoordinator() -> Coordinator { () }
}

/// The representable has no body — SwiftUI provides it through `Never`.
public extension UIViewRepresentable where Body == Never {
    var body: Never { fatalError("UIViewRepresentable has no body") }
}

/// `SwiftUI.UIViewRepresentableContext`.
public struct UIViewRepresentableContext<ViewType> where ViewType: UIViewRepresentable {

    /// The coordinator of the representable.
    public var coordinator: ViewType.Coordinator

    /// The environment of the representable.
    public var environment: EnvironmentValues

    public init(coordinator: ViewType.Coordinator, environment: EnvironmentValues? = nil) {
        self.coordinator = coordinator
        self.environment = environment ?? EnvironmentValues()
    }
}

// MARK: - The view controller representable

/// `SwiftUI.UIViewControllerRepresentable`.
public protocol UIViewControllerRepresentable: View where Body == Never {

    /// The UIKit view controller the representable manages.
    associatedtype UIViewControllerType: AnyObject

    /// The coordinator — `Void` when the representable needs none.
    associatedtype Coordinator = Void

    /// The context handed to the update methods.
    typealias Context = UIViewControllerRepresentableContext<Self>

    /// Creates the coordinator.
    func makeCoordinator() -> Coordinator

    /// Creates the UIKit view controller.
    func makeUIViewController(context: Context) -> UIViewControllerType

    /// Updates the UIKit view controller.
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
}

public extension UIViewControllerRepresentable where Coordinator == Void {
    func makeCoordinator() -> Coordinator { () }
}

/// The representable has no body — SwiftUI provides it through `Never`.
public extension UIViewControllerRepresentable where Body == Never {
    var body: Never { fatalError("UIViewControllerRepresentable has no body") }
}

/// `SwiftUI.UIViewControllerRepresentableContext`.
public struct UIViewControllerRepresentableContext<ViewType> where ViewType: UIViewControllerRepresentable {

    /// The coordinator of the representable.
    public var coordinator: ViewType.Coordinator

    /// The environment of the representable.
    public var environment: EnvironmentValues

    public init(coordinator: ViewType.Coordinator, environment: EnvironmentValues? = nil) {
        self.coordinator = coordinator
        self.environment = environment ?? EnvironmentValues()
    }
}
