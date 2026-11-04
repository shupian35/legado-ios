# Legado for iOS 阅读

A Swift port of the Android app [Legado / 阅读](https://github.com/gedoor/legado)
(`io.legado.app`) — the open-source novel reader whose rule DSL lets the users
script thousands of book sources without touching the code.

The port lives in this repository; the Android original is kept next to it, read
only, as the reference:

| path | what it is |
|---|---|
| `D:\code\vscode\legado` | the upstream Android app (the reference) |
| `D:\code\vscode\legado-ios` | this port |

The feature-by-feature status lives in
[`Plan/00-feature-parity-matrix.md`](Plan/00-feature-parity-matrix.md) — every
upstream feature is listed with its upstream file, the Swift implementation and
its state (`[x]` done, `[~]` partial, `[ ]` not started), followed by the
deliberate deviations.

The port is ~63,950 lines of Swift in 243 files, with ~14,130 lines of tests
(1,126 unit tests: 1,046 in `LegadoCoreTests`, 80 in `LegadoServerTests`) next to them.

## What is in here

```
Package.swift          the SwiftPM package
Sources/
  LegadoCore/          the whole engine: rules, matchers, storage, network,
                       the reader, the pipeline, the backups, the local API model
  LegadoUI/            the SwiftUI views (shared by iOS and macOS)
  LegadoUIShim/        a hand-written SwiftUI stand-in, so the same view
                       sources are type-checked by the Linux build
  LegadoServer/        the local HTTP + WebSocket server (the upstream web API)
  LegadoApp/           a command-line shell with a headless smoke test
  LegadoAppUI/         the iOS entry point (`@main`) + the Info.plist
Tests/                 1,126 unit tests
project.yml            the XcodeGen spec of the iOS application target
Scripts/
  sw.sh                the build/test/run helper (WSL, a clean PATH, a scratch dir)
  typecheck_apple.sh   type-checks the `#if canImport(UIKit)` blocks on Linux
  apple-stubs/         the Apple API stubs that make that check possible
```

### The modules

| target | what it does |
|---|---|
| `LegadoCore` | the platform-independent engine: the rule engine (CSS / XPath / JSONPath / regex / JavaScript), the Room-like storage (21 tables), the network layer, the reading engine (the page model, the pagination, the state machine), the local-book parsers (TXT / EPUB / UMD / PDF), the export, the backup, the WebDAV client, the Chinese converter, the manga mode, the read-aloud core |
| `LegadoUI` | the SwiftUI views: the bookshelf, the book detail and the table of contents, the reader, the discovery and the source manager, the RSS, the settings, the backup, the login, the source editor |
| `LegadoServer` | the upstream local API: 26 HTTP routes, the three WebSocket endpoints and the **upstream Vue web client** |
| `LegadoUIShim` | a SwiftUI stand-in used only on Linux, so the shared views are compiled and verified by the CI |

## Building

### The iOS application (a Mac is required)

The iOS bundle is an Xcode project generated from `project.yml`:

```bash
brew install xcodegen          # once
xcodegen generate              # writes LegadoApp.xcodeproj
open LegadoApp.xcodeproj       # then ⌘R to run, or:
xcodebuild -project LegadoApp.xcodeproj -scheme LegadoApp \
           -destination 'generic/platform=iOS' build
```

The project depends on the local SwiftPM package, so the shared code and the
app shell never drift apart. The bundle registers the `legado://` URL scheme
(the upstream deep links), the file sharing (the local book import) and the
ATS exceptions the HTTP book sources need.

### The engine and the tests (Linux, macOS or Windows + WSL)

The package itself builds and tests anywhere Swift runs:

```bash
swift build
swift test
```

On this machine the build runs inside WSL2 (Ubuntu 24.04 + Swift 6.4.2)
through the helper script, which pins a clean `PATH` and a scratch directory on
the persistent volume:

```bash
wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/sw.sh build
wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/sw.sh test
```

`Scripts/sw.sh run` starts the command-line shell, which runs a headless
smoke test (the schema, the groups, a source import, the bookshelf, the reader
pagination and the local API):

```
[ok] schema created (21 tables)
[ok] default groups: 全部
[ok] imported 1 book source(s)
[ok] bookshelf holds 1 book(s): 测试书
[ok] reader laid out 4 page(s) for 1800 characters
[ok] local API answered 200 on port 1122 (52 bytes)
[ok] web bookshelf served (1941 bytes)
[ok] websocket API port 1123 (= http + 1)
```

### The continuous integration

`.github/workflows/ios.yml` runs the Linux job (the package builds, the tests
run and the Apple-only code paths are type-checked) and the macOS job (the same,
plus the `xcodebuild` of the iOS bundle).

### The Apple-only code paths (the type check)

The `#if canImport(UIKit)` blocks — the in-app browser, the QR scanner, the
read-aloud, the notifications, the launcher icons, the PDF rendering — are
never compiled by the Linux build: the Swift parser checks their *syntax*, but
not their *types*. A typo in one of them would only surface when somebody opens
the project in Xcode.

`Scripts/typecheck_apple.sh` closes that gap on Linux. The stub modules under
`Scripts/apple-stubs` declare the Apple API the port uses, with the real
signatures, so `canImport(UIKit)` becomes true and the same sources are
type-checked with the Apple branches enabled:

```bash
wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/typecheck_apple.sh
# OK — the Apple-only code paths type-check
```

The stubs are never linked and never run — they exist for the type checker.
The check has already caught a dozen real iOS build errors (a missing
`makeUIView`, an `Image(platformImage:)`, a `Set` of the notification
categories, the actor isolation of `UIApplication`, a `WKWebView` without a
frame, an `Int` divided by a `Double`).

## The web bookshelf

The server serves the **upstream Vue application** — the very bundle that is
committed in the Android repository (`app/src/main/assets/web/vue`), copied
verbatim into `Sources/LegadoServer/Resources/WebUI` together with the upstream
help pages and the upload page. It talks to the port's HTTP API, which answers
with the upstream `ReturnData` envelope (`{isSuccess, errorMsg, data}`) and
keeps the business errors in `errorMsg` with the HTTP status 200, exactly like
`api/ReturnData.kt`. The WebSocket API listens on the HTTP port **+ 1**, the
address the upstream web client expects.

The upstream Android server has no authentication at all; the port requires a
bearer token, so the served `index.html` is patched with a small inline script
that adds the `Authorization` header to every request and the `token` query
parameter to the WebSocket URL. The browser experience is unchanged, but the
API is no longer open to the local network — which is the one security
difference the port deliberately introduces.

## The rules

The heart of Legado is its rule DSL: a book source is a set of strings that say
how to fetch and parse a website. The port keeps the semantics exactly — the
five strategies are dispatched **by prefix and never by fallback**, the marker
resolution, the `##` replacement, the `@put`/`@get` variables, the `&&`/`||`/`%%`
combinators, the element index syntax and the upstream quirks are all
reproduced. `Plan/00-feature-parity-matrix.md` lists them one by one, and the
"Known upstream quirks that are reproduced on purpose" section at its end lists
the surprising ones.

## The parity audits

Four read-only audits walked the upstream `app/src/main/java/io/legado/app/`
tree and compared every **user-visible** feature with the port. They found
that the first version of the feature matrix was **overstated**: a preference
key that exists in `AppSettings` is not a shipped feature unless a screen
actually lets the user change it — 566 upstream features, 85 present, 157
partial, 324 missing.

The port then closed the great majority of them (the source manager, the
replace rules, the theme list, the reader's settings, the RSS management, the
multi-source search, the reader's tip system, the click-region editor, the
read-aloud dialog, the text selection, the dictionary, the manga menu, …).
`Plan/00-feature-parity-matrix.md` §8 keeps the audit's own gap lists with a
state column, and **§8.6 is the honest remainder — 5 items, all of them
deliberate deviations**: the volume keys and the hardware page-turn keys need
a `UIApplication` subclass and Android key codes, the system TTS settings and
the "media button wakes the app" behaviour have no iOS equivalent, and the
`optimizeRender` canvas recorder is an Android API.

A **second wave** of four fresh audits (2026-11-04, the reports in
`Plan/audits/`) re-walked the same four areas and found ≈130 items the first
wave had missed — the in-app file browser of the local import, the manga's
horizontal scroll and zoom, the RSS favourites editor, the search row's
labels, the tip colour pickers, … They are listed in **§8.7** of the matrix
and are the current work list.

## The security differences from the Android app

The upstream app ships a few sharp edges that the port does **not** reproduce:

* the local HTTP API has no authentication and reflects the CORS origin — the
  port requires a bearer token and allows one configured origin;
* the `ReaderProvider` is an exported ContentProvider — the port exports a
  read-only snapshot instead;
* the private signing key and its password are committed in the upstream
  repository, and `app/google-services.json` carries a plaintext Firebase key;
* the rule scripts run in a Rhino sandbox with a class deny-list — the port
  grants the capabilities one by one (`ScriptCapabilities`).

## The licenses

The upstream app is GPL-3.0; this port follows the same license.
