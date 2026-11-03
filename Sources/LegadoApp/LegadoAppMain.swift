//
//  LegadoAppMain.swift
//  LegadoApp
//
//  The `@main` entry point of the port.
//
//  Upstream the Android app has `io.legado.app.ui.main.MainActivity` as its
//  launcher and `MyApplication` as its `Application` subclass. The Swift port
//  keeps the same shape: one scene with the four tabs of the upstream bottom
//  navigation (书架 / 发现 / 订阅 / 我的).
//
//  On Apple platforms this drives the real SwiftUI; on Linux it is compiled
//  against the `LegadoUIShim` so the entry point is type-checked by the CI
//  (the executable itself does nothing there).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore
import LegadoUI

@main
struct LegadoAppMain: App {

    @StateObject private var model = LegadoAppModel.makeDefault()

    init() {
        #if canImport(UserNotifications)
        // The upstream registers the three notification channels in
        // `App.kt:179-222`; the iOS port asks for the permission and
        // registers the categories when the app starts.
        //
        // `prepare()` is asynchronous (it asks the system for the
        // permission), so it runs in a task — an `init()` cannot await.
        Task { await NotificationService.shared.prepare() }
        #endif
        #if !canImport(SwiftUI)
        // There is no SwiftUI run loop on Linux, so the executable runs the
        // headless smoke test instead of opening a window.
        AppRuntime.shared.main = {
            LegadoSmokeTest.run(arguments: Array(CommandLine.arguments.dropFirst()))
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LegadoRootScene(model: model)
        }
    }
}
