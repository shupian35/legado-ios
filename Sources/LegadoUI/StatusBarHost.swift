//
//  StatusBarHost.swift
//  LegadoUI
//
//  Hides the status bar while the reader is open.
//
//  Upstream `ui/book/read/ReadBookActivity.kt` applies the preference
//  `hideStatusBar` through the window flags. SwiftUI has no modifier for it,
//  so the reader content is hosted in a `UIViewController` that reports
//  `prefersStatusBarHidden`.
//
//  The whole file is Apple-only; on Linux the reader renders the content
//  directly (the shim has no view-controller representable).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

#if canImport(UIKit) && !os(macOS)
import UIKit

/// Hosts the reader content so that the status bar can be hidden.
struct StatusBarHostController: UIViewControllerRepresentable {

    /// Whether the status bar is hidden.
    var isHidden: Bool

    /// The reader content.
    let content: AnyView

    func makeUIViewController(context: Context) -> HostController {
        let controller = HostController()
        controller.statusBarHidden = isHidden
        controller.host.rootView = content
        controller.addChild(controller.host)
        controller.view.addSubview(controller.host.view)
        controller.host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.host.view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            controller.host.view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            controller.host.view.topAnchor.constraint(equalTo: controller.view.topAnchor),
            controller.host.view.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        controller.host.didMove(toParent: controller)
        return controller
    }

    func updateUIViewController(_ controller: HostController, context: Context) {
        controller.statusBarHidden = isHidden
        controller.host.rootView = content
    }

    /// The hosting controller.
    final class HostController: UIViewController {
        // Not `isHidden` — that name belongs to `UIView` and overriding it
        // would hide the reader content together with the status bar.
        var statusBarHidden: Bool = false {
            didSet { setNeedsStatusBarAppearanceUpdate() }
        }
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        override var prefersStatusBarHidden: Bool { statusBarHidden }
        override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }
    }
}
#endif

/// Wraps the reader content so that the status bar can be hidden.
public struct ReaderStatusBarHost<Content: View>: View {

    /// Whether the status bar is hidden.
    let isHidden: Bool

    /// The reader content.
    @ViewBuilder let content: () -> Content

    public init(isHidden: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isHidden = isHidden
        self.content = content
    }

    public var body: some View {
        #if canImport(UIKit) && !os(macOS)
        StatusBarHostController(isHidden: isHidden, content: AnyView(content()))
        #else
        content()
        #endif
    }
}
