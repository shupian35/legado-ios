//
//  HttpTtsCache.swift
//  LegadoCore
//
//  The disk cache of the HTTP text-to-speech audio.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/service/HttpReadAloudService.kt
//    - line 88: the cache folder `cacheDir/httpTTS`
//    - line 414: `md5SpeakFileName(content, textChapter)`
//    - line 427: `hasSpeakFile(name)`
//    - line 435: `createSpeakFile(name, inputStream)`
//    - line 448: `clearTtsCache()`
//

import Foundation

/// The cache of the audio of the HTTP TTS engine.
///
/// The upstream downloads the audio of every paragraph into
/// `cacheDir/httpTTS/<md5(title)>_<md5(url-|-rate-|-text)>.mp3` and plays the
/// file; the same file is reused the next time the paragraph is spoken.
public enum HttpTtsCache {

    /// The folder of the cached audio — upstream `cacheDir/httpTTS`.
    public static func directory(root: URL) -> URL {
        root.appendingPathComponent("httpTTS", isDirectory: true)
    }

    /// The name of the cached file of a paragraph — upstream
    /// `md5SpeakFileName(content, textChapter)`.
    public static func fileName(
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> String {
        HttpTtsPlayback.fileName(
            text: text,
            chapterTitle: chapterTitle,
            ttsUrl: ttsUrl,
            speechRate: speechRate
        )
    }

    /// The URL of the cached file — upstream `getSpeakFileAsMd5(name)`.
    public static func fileURL(
        root: URL,
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> URL {
        let name = fileName(
            text: text,
            chapterTitle: chapterTitle,
            ttsUrl: ttsUrl,
            speechRate: speechRate
        )
        return directory(root: root).appendingPathComponent("\(name).mp3")
    }

    /// The cached audio of a paragraph — upstream `hasSpeakFile(name)` +
    /// the read of the file.
    public static func data(
        root: URL,
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> Data? {
        let url = fileURL(
            root: root,
            text: text,
            chapterTitle: chapterTitle,
            ttsUrl: ttsUrl,
            speechRate: speechRate
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Writes the audio of a paragraph into the cache — upstream
    /// `createSpeakFile(name, inputStream)`.
    @discardableResult
    public static func store(
        _ data: Data,
        root: URL,
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> Bool {
        let folder = directory(root: root)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = fileURL(
            root: root,
            text: text,
            chapterTitle: chapterTitle,
            ttsUrl: ttsUrl,
            speechRate: speechRate
        )
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Removes the whole cache — upstream `clearTtsCache()`.
    public static func removeAll(root: URL) {
        try? FileManager.default.removeItem(at: directory(root: root))
    }
}
