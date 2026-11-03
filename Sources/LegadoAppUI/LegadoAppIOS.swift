//
//  LegadoAppIOS.swift
//  LegadoAppUI
//
//  The iOS entry point of the port.
//
//  The SwiftPM package ships the shared view layer (`LegadoUI`) and a
//  command-line shell (`LegadoApp`). The iOS application is a thin Xcode
//  target that adds the `@main` scene, the bundle metadata and the deep-link
//  handler — everything else lives in the package.
//
//  Upstream the Android launcher is `io.legado.app.ui.main.MainActivity`; the
//  deep links are handled by `io.legado.app.ui.association.*`.
//

import SwiftUI
import LegadoCore
import LegadoUI

@main
struct LegadoAppIOS: App {

    @StateObject private var model = LegadoAppModel.makeDefault()

    var body: some Scene {
        WindowGroup {
            LegadoRootScene(model: model)
        }
    }
}
