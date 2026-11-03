//
//  UIImport.swift
//  LegadoUI
//
//  The single place that decides which SwiftUI the shared view layer talks to.
//
//  On Apple platforms the real SwiftUI is used; everywhere else the
//  `LegadoUIShim` stand-in is used so that the very same view sources are
//  type-checked by the Linux build and the Linux CI job.
//
//  Every other file of this module repeats the same `#if canImport(SwiftUI)`
//  dance — Swift imports are per file, so the alias cannot be shared.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The version of the port, shown in the "about" screen.
///
/// Upstream: `BuildConfig.VERSION_NAME` produced by the Gradle build.
public enum LegadoAppInfo {
    /// The upstream Android package the port mirrors.
    public static let upstreamPackage = "io.legado.app"
    /// The upstream source tree the port was written against.
    public static let upstreamPath = "app/src/main/java/io/legado/app"
    /// The version of the port.
    public static let version = "1.0.0"
}
