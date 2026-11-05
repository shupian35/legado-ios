//
//  HttpTtsPlayback.swift
//  LegadoCore
//
//  The playback plan of the HTTP TTS engine.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/service/HttpReadAloudService.kt
//  app/src/main/java/io/legado/app/constant/AppPattern.kt:45
//
//  The upstream has two delivery modes — the preference
//  `AppConfig.streamReadAloudAudio` decides whether the audio is downloaded
//  into a cache file (`downloadAndPlayAudios`) or streamed straight from the
//  server (`downloadAndPlayAudiosStream`). Both modes use the same plan: one
//  item per paragraph, the name of the cached file and the text that is
//  really sent to the service.
//

import Foundation

// MARK: - The delivery mode

/// How the audio of the HTTP TTS engine is delivered — upstream
/// `AppConfig.streamReadAloudAudio`.
public enum HttpTtsDelivery: String, CaseIterable, Sendable {
    /// The audio is downloaded and played from the memory — upstream
    /// `downloadAndPlayAudios()`.
    case download
    /// The audio is streamed from the server — upstream
    /// `downloadAndPlayAudiosStream()`.
    case stream

    /// The upstream default is `false` — the audio is downloaded.
    public static let `default`: HttpTtsDelivery = .download
}

// MARK: - One item of the plan

/// One paragraph of the read aloud and the audio that belongs to it.
public struct HttpTtsItem: Equatable, Sendable {

    /// The text of the paragraph.
    public let text: String
    /// The text that is sent to the TTS service — upstream
    /// `speakText = text.replace(AppPattern.notReadAloudRegex, "")`.
    ///
    /// It is empty when the paragraph holds nothing worth speaking (only
    /// punctuation, whitespace, control characters, separators or symbols);
    /// the upstream then plays a silent sound instead.
    public let speakText: String
    /// The name of the cached audio — upstream `md5SpeakFileName(content)`.
    public let fileName: String

    public init(text: String, speakText: String, fileName: String) {
        self.text = text
        self.speakText = speakText
        self.fileName = fileName
    }

    /// Whether the paragraph is silent — upstream: an empty `speakText` is
    /// replaced by a silent sound (`createSilentSound`).
    public var isSilent: Bool { speakText.isEmpty }
}

// MARK: - The plan

/// Builds the playback plan of the HTTP TTS engine — upstream
/// `HttpReadAloudService`.
public enum HttpTtsPlayback {

    /// The name of the cached audio file — upstream
    /// `md5SpeakFileName(content, textChapter)`:
    /// `md5Encode16(chapterTitle) + "_" + md5Encode16("url-|-rate-|-content")`.
    public static func fileName(
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> String {
        let title = ScriptDigest.md5Encode16(chapterTitle)
        // Upstream: `"${httpTts.url}-|-$speechRate-|-$content"`.
        let content = ScriptDigest.md5Encode16("\(ttsUrl)-|-\(speechRate)-|-\(text)")
        return "\(title)_\(content)"
    }

    /// The text that is really sent to the service — upstream
    /// `text.replace(AppPattern.notReadAloudRegex, "")`.
    ///
    /// The upstream regex is anchored, so the whole paragraph is removed when
    /// it holds nothing worth speaking.
    public static func speakText(_ text: String) -> String {
        ReadAloudSplitter.isSkipped(text) ? "" : text
    }

    /// One item of the plan.
    public static func item(
        text: String,
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> HttpTtsItem {
        HttpTtsItem(
            text: text,
            speakText: speakText(text),
            fileName: fileName(
                text: text,
                chapterTitle: chapterTitle,
                ttsUrl: ttsUrl,
                speechRate: speechRate
            )
        )
    }

    /// The plan of the paragraphs of one chapter — upstream
    /// `contentList.forEachIndexed { … }`.
    ///
    /// The upstream skips the paragraphs that were already spoken
    /// (`index < nowSpeak`); the caller passes the remaining paragraphs.
    public static func plan(
        paragraphs: [String],
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int
    ) -> [HttpTtsItem] {
        paragraphs.map {
            item(
                text: $0,
                chapterTitle: chapterTitle,
                ttsUrl: ttsUrl,
                speechRate: speechRate
            )
        }
    }

    /// The paragraphs of the next chapter that are pre-downloaded — upstream
    /// `preDownloadAudios`: the first ten paragraphs of the next chapter.
    public static func preDownloadPlan(
        paragraphs: [String],
        chapterTitle: String,
        ttsUrl: String,
        speechRate: Int,
        limit: Int = 10
    ) -> [HttpTtsItem] {
        plan(
            paragraphs: Array(paragraphs.prefix(limit)),
            chapterTitle: chapterTitle,
            ttsUrl: ttsUrl,
            speechRate: speechRate
        )
    }

    /// The text of a paragraph that is really sent to the service, with the
    /// part that was already spoken removed — upstream
    /// `text = text.substring(paragraphStartPos)`.
    public static func remainingText(_ text: String, from position: Int) -> String {
        guard position > 0 else { return text }
        let characters = Array(text)
        guard position < characters.count else { return "" }
        return String(characters[position...])
    }
}
