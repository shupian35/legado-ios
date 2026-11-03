#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit)
import UIKit

/// The system share sheet — upstream `ui/association/` shares a book source
/// as a JSON string.
public struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#else

/// The share sheet without a UI (the Linux build has no share sheet).
public struct ShareSheet: View {

    let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public var body: some View {
        Text("当前平台不支持分享")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
    }
}

#endif
