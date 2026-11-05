//
//  SimulatedReadingView.swift
//  LegadoUI
//
//  The simulated reading — upstream
//  `ui/book/read/BaseReadBookActivity.kt:290` (`showSimulatedReading`).
//
//  With the simulation on the chapters unlock day by day: the book starts at
//  `startChapter` and every day `dailyChapters` further chapters are
//  unlocked (upstream `Book.simulatedTotalChapterNum()`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The settings of the simulated reading.
public struct SimulatedReadingView: View {

    /// The book whose simulation is configured.
    let book: Book

    /// Called with the new configuration when the user saves.
    let onSave: (BookReadConfig) -> Void

    @State private var enabled: Bool
    @State private var startChapter: String
    @State private var dailyChapters: String
    @State private var startDate: String

    public init(book: Book, onSave: @escaping (BookReadConfig) -> Void) {
        self.book = book
        self.onSave = onSave
        let config = book.readConfigBox
        _enabled = State(wrappedValue: config.readSimulating)
        _startChapter = State(wrappedValue: "\(config.startChapter ?? 0)")
        _dailyChapters = State(wrappedValue: "\(config.dailyChapters)")
        _startDate = State(wrappedValue: config.startDate ?? SimulatedReadingView.today())
    }

    public var body: some View {
        Form {
            Section {
                Toggle("启用模拟阅读", isOn: $enabled)
            }
            Section("开始章节") {
                TextField("开始章节", text: $startChapter)
                    .legadoNumberPadKeyboard()
            }
            Section("每日解锁章节数") {
                TextField("每日解锁章节数", text: $dailyChapters)
                    .legadoNumberPadKeyboard()
            }
            Section("开始日期") {
                TextField("yyyy-MM-dd", text: $startDate)
                Text("格式：yyyy-MM-dd")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Section {
                Button("保存") {
                    save()
                }
            }
        }
        .navigationTitle("模拟阅读")
    }

    /// Saves the configuration — upstream `BaseReadBookActivity.showSimulatedReading()`
    /// writes the four values into the book and saves it.
    private func save() {
        var config = book.readConfigBox
        config.readSimulating = enabled
        config.startChapter = Int(startChapter) ?? 0
        config.dailyChapters = Int(dailyChapters) ?? Int(book.totalChapterNum)
        let trimmed = startDate.trimmingCharacters(in: .whitespacesAndNewlines)
        config.startDate = trimmed.isEmpty ? SimulatedReadingView.today() : trimmed
        onSave(config)
    }

    /// Today's date in the upstream's format.
    public static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
