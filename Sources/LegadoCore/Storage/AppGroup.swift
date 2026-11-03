//
//  AppGroup.swift
//  LegadoCore
//
//  The shared container.
//
//  Upstream exports the library to other apps through the exported
//  `ContentProvider` (`api/ReaderProvider.kt`). iOS has no equivalent IPC
//  surface, so the port keeps the data in an App Group container: an
//  extension (a widget, a share extension) can then open the same SQLite
//  file, and the table names stay the ones the upstream uses so that a
//  backup or a third-party tool can read them.
//

import Foundation

/// The App Group of the app.
public enum AppGroup {

    /// The App Group identifier (must match the entitlement of the target).
    public static let identifier = "group.io.legado.ios.Legado"

    /// The file name of the database inside the container.
    public static let databaseFileName = "legado.sqlite"

    /// The container of the App Group, or `nil` when the app has no
    /// entitlement (or when it runs on a platform without App Groups).
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        #if canImport(Darwin)
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        // App Groups are an Apple platform feature; the Linux build (the one
        // the port is verified on) has no shared container.
        return nil
        #endif
    }

    /// The database file inside the shared container.
    public static func databaseURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    /// The directory the shared files live in (the cache, the fonts, …).
    public static func sharedDirectory(
        named name: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let container = containerURL(fileManager: fileManager) else { return nil }
        let directory = container.appendingPathComponent(name, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
