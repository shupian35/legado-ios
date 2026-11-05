//
//  ShareLayout.swift
//  LegadoCore
//
//  The shared layout — upstream `ReadBookConfig`.
//
//  The upstream keeps a second layout configuration next to the current one
//  (`ReadBookConfig.shareConfig`, stored in `shareReadConfig.json`) and uses it
//  when the content is shared:
//
//      val config get() = if (shareLayout) shareConfig else durConfig
//
//  The export uses a copy of the current layout whose layout fields are taken
//  from the shared one:
//
//      fun getExportConfig(): Config {
//          val exportConfig = durConfig.copy()
//          if (shareLayout) {
//              exportConfig.textFont = shareConfig.textFont
//              ...
//          }
//          return exportConfig
//      }
//

import Foundation

/// The shared layout — upstream `ReadBookConfig.shareConfig`.
public enum ShareLayout {

    /// The name of the file the shared layout is stored in — upstream
    /// `ReadBookConfig.shareConfigFileName`.
    public static let configFileName = "shareReadConfig.json"

    /// The layout fields the export takes from the shared layout — upstream
    /// `ReadBookConfig.getExportConfig`.
    ///
    /// The upstream only replaces the fields when the shared layout is on
    /// (`if (shareLayout) { … }`).
    public static func exportConfig(
        current: ReaderConfig,
        share: ReaderConfig,
        enabled: Bool = true
    ) -> ReaderConfig {
        guard enabled else { return current }
        var export = current
        export.textBold = share.textBold
        export.textSize = share.textSize
        export.letterSpacing = share.letterSpacing
        export.lineSpacingExtra = share.lineSpacingExtra
        export.paragraphSpacing = share.paragraphSpacing
        export.titleMode = share.titleMode
        export.titleSize = share.titleSize
        export.titleTopSpacing = share.titleTopSpacing
        export.titleBottomSpacing = share.titleBottomSpacing
        export.paddingBottom = share.paddingBottom
        export.paddingLeft = share.paddingLeft
        export.paddingRight = share.paddingRight
        export.paddingTop = share.paddingTop
        export.textColor = share.textColor
        export.textColorNight = share.textColorNight
        export.textColorEInk = share.textColorEInk
        return export
    }

    /// The layout that is used — upstream
    /// `ReadBookConfig.config get() = if (shareLayout) shareConfig else durConfig`.
    public static func effective(
        current: ReaderConfig,
        share: ReaderConfig?,
        enabled: Bool
    ) -> ReaderConfig {
        guard enabled, let share else { return current }
        return share
    }
}
