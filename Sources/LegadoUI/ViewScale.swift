//
//  ViewScale.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/manga/recyclerview/WebtoonRecyclerView.kt
//  (the pinch zoom of the manga reader).
//
//  `CGFloat` does not exist on Linux, so the shared view layer cannot pass a
//  `Double` to the SwiftUI APIs that expect a `CGFloat`. These helpers hide
//  the difference.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

/// Scales a view — `scaleEffect(_:anchor:)` expects a `CGFloat` on Apple.
@inline(__always)
public func scaled<V: View>(_ view: V, by factor: Double) -> some View {
    #if canImport(CoreGraphics)
    return view.scaleEffect(CGFloat(factor))
    #else
    return view.scaleEffect(factor)
    #endif
}

/// Blurs a view — `blur(radius:)` expects a `CGFloat` on Apple.
///
/// Upstream reference: `base/BaseActivity.kt:162-174` (`upBackgroundImage`) and
/// `help/config/ThemeConfig.kt:79-100` (`getBgImage`).
@inline(__always)
public func blurred<V: View>(_ view: V, radius: Double) -> some View {
    #if canImport(CoreGraphics)
    return view.blur(radius: CGFloat(radius))
    #else
    return view.blur(radius: radius)
    #endif
}
