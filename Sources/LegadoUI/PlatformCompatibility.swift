//
//  PlatformCompatibility.swift
//  LegadoUI
//
//  The SwiftUI modifiers the shared views use that only exist on iOS.
//
//  `LegadoUI` is built for iOS (inside the app) and for macOS (by the
//  `swift build` of the CI job), so a modifier that is unavailable on macOS
//  must be a no-op there instead of failing to compile. Keeping the
//  `#if os(iOS)` in one place means the views themselves stay readable.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

extension View {

    /// `navigationBarTitleDisplayMode(.inline)` — iOS only.
    @ViewBuilder
    func legadoInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// `textInputAutocapitalization(.never)` — iOS only.
    @ViewBuilder
    func legadoNoAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// `keyboardType(.numberPad)` — iOS only.
    @ViewBuilder
    func legadoNumberPadKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
