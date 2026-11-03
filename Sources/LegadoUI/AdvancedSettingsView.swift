#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The advanced settings — every upstream `PreferKey` is editable.
///
/// The upstream settings screen (`ui/config/*`) shows a hand-picked subset of
/// the ~200 preferences; the port exposes them all with their raw values so
/// that no preference is out of reach (documented deviation).
public struct AdvancedSettingsView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var filter: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(keys, id: \.rawValue) { key in
                SettingRow(key: key, model: model)
            }
        }
        .navigationTitle("全部设置")
        .searchable(text: $filter, prompt: "搜索设置项")
    }

    private var keys: [SettingsKey] {
        let all = SettingsKey.allCases
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { key in
            key.rawValue.lowercased().contains(query)
        }
    }
}

/// One preference.
struct SettingRow: View {

    let key: SettingsKey
    @ObservedObject var model: LegadoAppModel
    @State private var value: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.rawValue)
                .font(.system(size: 13))
            TextField("值", text: $value)
                .font(.system(size: 13))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    save()
                }
        }
        .onAppear {
            value = model.environment.settings.string(key) ?? ""
        }
    }

    private func save() {
        model.environment.settings.set(value.isEmpty ? nil : value, for: key)
    }
}
