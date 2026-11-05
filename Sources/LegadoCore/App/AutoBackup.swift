//
//  AutoBackup.swift
//  LegadoCore
//
//  The daily automatic backup — the port of the upstream
//  `app/src/main/java/io/legado/app/help/storage/Backup.kt` (`autoBack`) and
//  `app/src/main/java/io/legado/app/help/AppWebDav.kt` (`upBgs`).
//
//  Upstream semantics:
//
//  * `Backup.shouldBackup()` — a backup is due when the last one is more than
//    a day old. The time of the last backup lives in `LocalConfig.lastBackup`.
//  * `Backup.autoBack(context)` — called when the main activity is destroyed
//    (that is, when the app is closed). Under a mutex it checks again, builds
//    the name of today's backup and, **only when the server does not hold a
//    file with that name**, makes the backup and uploads it. Otherwise it
//    merely moves `lastBackup` forward.
//  * `AppWebDav.upBgs(files)` — after the backup the reader background images
//    are uploaded to the `background/` folder; the ones the server already
//    holds are skipped.
//

import Foundation

/// The daily automatic backup.
public enum AutoBackup {

    /// Whether the daily backup is due — upstream `Backup.shouldBackup()`.
    ///
    /// The upstream backs up once a day; the time of the last backup is kept
    /// in `LocalConfig.lastBackup`.
    public static func shouldBackup(lastBackup: Date?, now: Date = Date()) -> Bool {
        let last = lastBackup ?? .distantPast
        return last.addingTimeInterval(86_400) < now
    }

    /// The names of the background images of the reader presets — upstream
    /// `ReadBookConfig.getAllPicBgStr()`.
    ///
    /// Only the backgrounds whose type is "a user image" (2) count — the
    /// colours and the bundled assets are not files.
    public static func backgroundImageNames(presets: [ReaderBackgroundPreset]) -> [String] {
        var names: [String] = []
        for preset in presets {
            if preset.bgType == 2 { names.append(preset.bgStr) }
            if preset.bgTypeNight == 2 { names.append(preset.bgStrNight) }
            if preset.bgTypeEInk == 2 { names.append(preset.bgStrEInk) }
        }
        return names
    }

    /// The background images the server does not hold yet — upstream
    /// `AppWebDav.upBgs()`.
    ///
    /// The upstream compares the file names with the names of the remote
    /// files and uploads only the missing ones.
    public static func pendingBackgrounds(
        local: [(name: String, data: Data)],
        remote: [String]
    ) -> [(name: String, data: Data)] {
        local.filter { !remote.contains($0.name) }
    }

    /// The background image files of the presets, read from the local
    /// background folder.
    ///
    /// - Parameters:
    ///   - presets: the reader background presets.
    ///   - root: the folder the background images live in — upstream
    ///     `<externalFiles>`; a name that contains a separator is used as it is.
    public static func backgroundFiles(
        presets: [ReaderBackgroundPreset],
        root: URL
    ) -> [(name: String, data: Data)] {
        var result: [(name: String, data: Data)] = []
        var seen: Set<String> = []
        for name in backgroundImageNames(presets: presets) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            let url = ReaderBackground.filePath(for: trimmed, root: root)
            guard let data = try? Data(contentsOf: url) else { continue }
            result.append((name: url.lastPathComponent, data: data))
        }
        return result
    }
}
