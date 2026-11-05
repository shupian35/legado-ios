//
//  TtsEngine.swift
//  LegadoCore
//
//  The resolution of the read-aloud engine — upstream `model/ReadAloud.kt:24-35`
//  and `ui/book/read/config/SpeakEngineDialog.kt`.
//
//  The upstream stores the engine twice: `AppConfig.ttsEngine` is the global
//  default and `Book.config.ttsEngine` overrides it for one book. The value
//  is either the id of an `HttpTTS` row (a number) or the JSON of an Android
//  system engine — the port only supports the HTTP TTS profiles.
//

import Foundation

/// The read-aloud engine of the reader.
public enum TtsEngine {

    /// The engine that is used — upstream `ReadAloud.ttsEngine`:
    /// `ReadBook.book?.getTtsEngine() ?: AppConfig.ttsEngine`.
    ///
    /// The engine of the book wins over the global one; a blank value is
    /// ignored.
    public static func resolve(bookEngine: String?, globalEngine: String?) -> String? {
        if let bookEngine {
            let trimmed = bookEngine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let globalEngine {
            let trimmed = globalEngine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// The id of the HTTP TTS profile of an engine value.
    ///
    /// Upstream `ReadAloud.kt:32-33`: only a numeric value is an HTTP TTS
    /// profile (`appDb.httpTTSDao.get(ttsEngine.toLong())`); anything else is
    /// the JSON of an Android system engine, which the port does not have.
    public static func profileId(of engine: String?) -> Int64? {
        guard let engine else { return nil }
        let trimmed = engine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) else { return nil }
        return Int64(trimmed)
    }

    /// The HTTP TTS profile of an engine value — upstream
    /// `appDb.httpTTSDao.get(ttsEngine.toLong())`.
    public static func profile(
        of engine: String?,
        store: LegadoStore
    ) -> HttpTTS? {
        guard let id = profileId(of: engine) else { return nil }
        return (try? store.httpTTS(id: id)) ?? nil
    }

    /// The engine value of a book — upstream `Book.getTtsEngine()`.
    public static func engine(of book: Book?) -> String? {
        guard let engine = book?.readConfigBox.ttsEngine else { return nil }
        let trimmed = engine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
