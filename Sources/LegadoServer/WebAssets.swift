//
//  WebAssets.swift
//  LegadoServer
//
//  The web bookshelf.
//
//  Upstream ships a Vue 3 single page application (`modules/web`, built by
//  its own CI into `app/src/main/assets/web/vue`) that talks to the local
//  HTTP API. The port serves **that very bundle** — it is copied verbatim
//  into `Resources/WebUI` — so the browser experience is identical to the
//  Android app, including the source editor and the source debug console.
//
//  The upstream client needs no token (the Android server has no
//  authentication at all); the port requires a bearer token, so the served
//  `index.html` is patched with a small inline script that adds the
//  `Authorization` header to every same-origin request and the `token`
//  query parameter to the WebSocket URL.
//
//  A tiny plain HTML/JavaScript client is kept as the fallback for the case
//  where the bundle is not part of the build.
//

import Foundation

/// The static assets of the web bookshelf.
public enum WebAssets {

    /// The paths the assets are served under.
    public static let indexPath = "/"
    public static let scriptPath = "/app.js"
    public static let stylePath = "/style.css"

    /// The token the web client has to present. `nil` disables it.
    public static var accessToken: String?

    /// The response for a path, or `nil` when the path is not an asset.
    public static func response(for path: String) -> HTTPResponseMessage? {
        // The upstream bundle first: it is the real web UI.
        if let response = upstreamResponse(for: path) { return response }
        switch path {
        case indexPath, "/index.html":
            return html(indexHTML)
        case scriptPath:
            return text(appJS, contentType: "application/javascript")
        case stylePath:
            return text(styleCSS, contentType: "text/css")
        default:
            return nil
        }
    }

    /// Whether the upstream Vue bundle is part of the build.
    public static var hasUpstreamBundle: Bool { upstreamBundle != nil }

    // MARK: - The upstream bundle

    /// The root of the copied upstream bundle.
    private static let upstreamBundle: URL? = {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "WebUI", withExtension: nil)
        #else
        return nil
        #endif
    }()

    /// Serves a file of the upstream bundle.
    private static func upstreamResponse(for path: String) -> HTTPResponseMessage? {
        guard let root = upstreamBundle else { return nil }
        var relative = path == "/" || path.isEmpty ? "index.html" : String(path.dropFirst())
        // Upstream keeps the Vue application in the `web/vue` folder, so the
        // bundle is reachable under `/vue/` as well.
        if relative.hasPrefix("vue/") {
            relative = String(relative.dropFirst("vue/".count))
            if relative.isEmpty { relative = "index.html" }
        }
        guard !relative.isEmpty, !relative.contains("..") else { return nil }
        let file = root.appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: file) else { return nil }
        if relative == "index.html" {
            // Patch the token into the page.
            var response = HTTPResponseMessage.binary(data, contentType: "text/html; charset=utf-8")
            let html = String(decoding: data, as: UTF8.self)
            response.body = Data((tokenScript + html).utf8)
            return response
        }
        return HTTPResponseMessage.binary(data, contentType: contentType(for: relative))
    }

    /// The content type of a bundle file.
    private static func contentType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    /// The inline script that teaches the upstream client to send the token.
    ///
    /// The upstream web client does not know about authentication (the Android
    /// server has none), so the port injects the header itself. The script is
    /// deliberately tiny and defensive: when no token is configured it does
    /// nothing at all.
    private static var tokenScript: String {
        guard let token = accessToken, !token.isEmpty else { return "" }
        let escaped = token.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        <script>
        (function () {
          var token = '\(escaped)';
          if (!token) { return; }
          var originalOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            this.__legadoToken = token;
            return originalOpen.apply(this, arguments);
          };
          var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
          XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
            if (name.toLowerCase() === 'authorization') { return; }
            if (this.__legadoToken && /^https?:\\/\\//i.test(String(arguments[1] || ''))) {
              return originalSetHeader.call(this, 'Authorization', 'Bearer ' + this.__legadoToken);
            }
            return originalSetHeader.apply(this, arguments);
          };
          var NativeWebSocket = window.WebSocket;
          if (NativeWebSocket) {
            window.WebSocket = function (url, protocols) {
              try {
                var parsed = new URL(url, window.location.href);
                if (parsed.host === window.location.host) {
                  parsed.searchParams.set('token', token);
                  url = parsed.toString();
                }
              } catch (e) {}
              return new NativeWebSocket(url, protocols);
            };
            window.WebSocket.prototype = NativeWebSocket.prototype;
            ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (key, index) {
              window.WebSocket[key] = NativeWebSocket[key];
            });
          }
        })();
        </script>
        """
    }

    private static func html(_ body: String) -> HTTPResponseMessage {
        var response = HTTPResponseMessage(code: 200)
        response.headers["Content-Type"] = "text/html; charset=utf-8"
        response.headers["Cache-Control"] = "no-store"
        response.body = Data(body.utf8)
        return response
    }

    private static func text(_ body: String, contentType: String) -> HTTPResponseMessage {
        var response = HTTPResponseMessage(code: 200)
        response.headers["Content-Type"] = contentType
        response.headers["Cache-Control"] = "no-store"
        response.body = Data(body.utf8)
        return response
    }

    /// The single page application.
    public static let indexHTML = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>阅读 · Web</title>
    <link rel="stylesheet" href="/style.css">
    </head>
    <body>
    <header>
      <h1>阅读</h1>
      <div id="tokenBox">
        <input id="token" type="password" placeholder="访问令牌">
        <button id="saveToken">保存</button>
      </div>
    </header>
    <nav id="groups"></nav>
    <main>
      <section id="books"></section>
      <section id="reader" hidden>
        <h2 id="readerTitle"></h2>
        <ol id="chapters"></ol>
        <article id="content"></article>
      </section>
    </main>
    <script src="/app.js"></script>
    </body>
    </html>
    """

    /// The client script.
    public static let appJS = """
    'use strict';

    const state = { token: localStorage.getItem('legadoToken') || '', group: -1, book: null };

    function headers() {
      const h = { 'Content-Type': 'application/json' };
      if (state.token) { h['Authorization'] = 'Bearer ' + state.token; }
      return h;
    }

    async function api(path) {
      const response = await fetch(path, { headers: headers() });
      if (response.status === 401) {
        document.getElementById('tokenBox').hidden = false;
        throw new Error('需要访问令牌');
      }
      if (!response.ok) { throw new Error(await response.text()); }
      const text = await response.text();
      if (!text) { return null; }
      // The upstream wraps every payload in `ReturnData`
      // (`isSuccess`, `errorMsg`, `data`).
      const envelope = JSON.parse(text);
      if (envelope && envelope.isSuccess === false) {
        throw new Error(envelope.errorMsg || '请求失败');
      }
      return envelope && 'data' in envelope ? envelope.data : envelope;
    }

    function element(tag, className, text) {
      const node = document.createElement(tag);
      if (className) { node.className = className; }
      if (text !== undefined && text !== null) { node.textContent = text; }
      return node;
    }

    async function loadBookshelf() {
      // The upstream `/getBookshelf` answers with the book array.
      const books = await api('/getBookshelf');
      const groups = document.getElementById('groups');
      groups.innerHTML = '';
      renderBooks(Array.isArray(books) ? books : ((books && books.books) || []));
    }

    function renderBooks(books) {
      const container = document.getElementById('books');
      container.innerHTML = '';
      books.forEach((book) => {
        const card = element('div', 'book');
        card.appendChild(element('h3', 'title', book.name));
        card.appendChild(element('div', 'author', book.author || ''));
        if (book.coverUrl) {
          const cover = element('img', 'cover');
          cover.src = book.coverUrl;
          cover.loading = 'lazy';
          card.appendChild(cover);
        }
        card.onclick = () => openBook(book);
        container.appendChild(card);
      });
    }

    async function openBook(book) {
      state.book = book;
      document.getElementById('reader').hidden = false;
      document.getElementById('readerTitle').textContent = book.name;
      const list = document.getElementById('chapters');
      list.innerHTML = '';
      const chapters = await api('/getChapterList?url=' + encodeURIComponent(book.bookUrl));
      chapters.forEach((chapter) => {
        const item = element('li', 'chapter', chapter.title);
        item.onclick = () => openChapter(chapter);
        list.appendChild(item);
      });
      if (chapters.length) { openChapter(chapters[0]); }
    }

    async function openChapter(chapter) {
      const content = document.getElementById('content');
      content.textContent = '加载中…';
      const url = '/getBookContent?url=' + encodeURIComponent(state.book.bookUrl)
        + '&index=' + chapter.index;
      const text = await api(url);
      content.textContent = text || '';
      content.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    document.getElementById('saveToken').onclick = () => {
      state.token = document.getElementById('token').value.trim();
      localStorage.setItem('legadoToken', state.token);
      loadBookshelf().catch((error) => alert(error.message));
    };

    loadBookshelf().catch((error) => {
      document.getElementById('books').textContent = error.message;
    });
    """

    /// The stylesheet.
    public static let styleCSS = """
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
      background: #f5f5f5;
      color: #222;
    }
    header {
      display: flex; align-items: center; gap: 12px;
      padding: 12px 16px; background: #795548; color: #fff;
    }
    header h1 { font-size: 18px; margin: 0; }
    #tokenBox { margin-left: auto; display: flex; gap: 6px; }
    #tokenBox input { padding: 4px 8px; border: none; border-radius: 4px; }
    #tokenBox button { padding: 4px 10px; border: none; border-radius: 4px; }
    nav { display: flex; gap: 8px; padding: 10px 16px; overflow-x: auto; }
    nav .group {
      border: 1px solid #ccc; background: #fff; border-radius: 16px;
      padding: 4px 12px; white-space: nowrap; cursor: pointer;
    }
    main { display: grid; grid-template-columns: 1fr; gap: 16px; padding: 0 16px 32px; }
    @media (min-width: 900px) { main { grid-template-columns: 320px 1fr; } }
    #books { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 12px; }
    .book {
      background: #fff; border-radius: 8px; padding: 10px; cursor: pointer;
      box-shadow: 0 1px 3px rgba(0,0,0,.12);
    }
    .book .title { font-size: 15px; margin: 0 0 4px; }
    .book .author { font-size: 12px; color: #666; }
    .book .cover { width: 100%; border-radius: 4px; margin-top: 8px; }
    #reader { background: #fff; border-radius: 8px; padding: 16px; }
    #reader h2 { margin-top: 0; font-size: 18px; }
    #chapters { max-height: 240px; overflow-y: auto; padding-left: 20px; }
    #chapters .chapter { cursor: pointer; padding: 4px 0; }
    #chapters .chapter:hover { color: #e53935; }
    #content { line-height: 1.8; white-space: pre-wrap; }
    """
}
