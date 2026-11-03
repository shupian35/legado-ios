//
//  ClickRegionEditorView.swift
//  LegadoUI
//
//  The click-region editor of the reader — upstream
//  `ui/book/read/config/ClickActionConfigDialog.kt`.
//
//  The upstream screen shows the nine regions of the page (a 3×3 grid) and
//  lets the user choose the action of every region; the choice is written
//  into the `clickActionTopLeft` … `clickActionBottomRight` preferences.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The click-region editor.
public struct ClickRegionEditorView: View {

    /// The preferences — the actions are written into them.
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("点击区域") {
                ForEach(TapZone.allCases, id: \.rawValue) { zone in
                    Picker(
                        ClickRegionEditorView.name(of: zone),
                        selection: Binding(
                            get: { action(for: zone) },
                            set: { value in
                                settings.setClickAction(value, for: zone.clickRegion)
                            }
                        )
                    ) {
                        ForEach(ClickAction.allCases, id: \.rawValue) { action in
                            Text(action.name).tag(action.rawValue)
                        }
                    }
                }
            }
            Section {
                Text("中间区域默认为菜单；若所有区域都没有设置菜单动作，中间区域会自动恢复为菜单（与上游 detectClickArea 一致）。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("点击区域")
    }

    /// The action of a zone — the upstream default is used when the
    /// preference was never written.
    private func action(for zone: TapZone) -> Int {
        let stored = settings.clickAction(zone.clickRegion)
        if ClickAction(rawValue: stored) != nil { return stored }
        return zone.defaultAction.rawValue
    }

    /// The name of a zone — upstream `ClickActionConfigDialog`.
    public static func name(of zone: TapZone) -> String {
        switch zone {
        case .topLeft: return "左上"
        case .topCenter: return "上中"
        case .topRight: return "右上"
        case .middleLeft: return "左中"
        case .middleCenter: return "正中"
        case .middleRight: return "右中"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "下中"
        case .bottomRight: return "右下"
        }
    }
}
