# Upstream spec — read aloud (TTS) + nine-zone tap mapping + page turning

Porting reference distilled from the Android sources in `D:\code\vscode\legado`.
Every line reference below points at the upstream Kotlin file.

---

## 1. Read aloud

### 1.1 Files

| File | Role |
|---|---|
| `app/src/main/java/io/legado/app/service/BaseReadAloudService.kt` (784) | shared state machine |
| `app/src/main/java/io/legado/app/service/TTSReadAloudService.kt` (266) | local `TextToSpeech` engine |
| `app/src/main/java/io/legado/app/service/HttpReadAloudService.kt` (617) | HTTP TTS (remote audio) |
| `app/src/main/java/io/legado/app/data/entities/HttpTTS.kt` (84) | the HTTP TTS profile |
| `app/src/main/java/io/legado/app/model/ReadAloud.kt` (137) | facade used by the UI |
| `app/src/main/java/io/legado/app/constant/EventBus.kt` | `ALOUD_STATE` (`"aloud_state"`), `TTS_PROGRESS` |

### 1.2 Lifecycle

* `ReadAloud.play()` → `IntentAction.play` → `newReadAloud(play, pageIndex, startPos)` → `play()`.
* The service state is published through `EventBus.ALOUD_STATE` with the states
  `PLAY` / `PAUSE` / `STOP`; the progress is published through `TTS_PROGRESS`.
* `BaseReadAloudService.isPlay()` is the "is it currently speaking" query used by
  the click action 13 (pause / resume).

### 1.3 What is spoken — the unit is the PARAGRAPH, not the sentence

The content of a chapter is split with `split("\n")` and every non-empty line is
one speakable unit:

```
getNeedReadAloud(...).split("\n").filter { it.isNotEmpty() }
```

A paragraph is **skipped** when it matches

```
notReadAloudRegex = "^(\s|\p{C}|\p{P}|\p{Z}|\p{S})+$"
```

i.e. it contains nothing but whitespace, control, punctuation, separators or
symbols (a decorative line of `……` or `---` is never spoken).

### 1.4 Position mapping (how the UI highlights what is being read)

* `readAloudNumber` — the character offset **inside the chapter** of the paragraph
  that is currently being spoken.
* `nowSpeak` — the index of the paragraph inside the chapter.
* The spoken paragraph is mapped onto the visible page with a binary search over
  `page.chapterPosition`:

```
pageIndex = page.chapterPosition binary search for readAloudNumber
aloudSpanStart = chapterStart - getReadLength(pageIndex)
```

* The highlight covers the **whole paragraph** (`upPageAloudSpan`).

### 1.5 HTTP TTS

* The response is **raw binary audio** — not base64, not a JSON envelope.
* One HTTP request per paragraph. In non-stream mode all requests are issued
  **up front**; in stream mode (`streamReadAloudAudio`) the next request is
  issued when the current one finishes.
* `HttpTTS.contentType` is a **regular expression** the response `Content-Type`
  must match.
* Timeouts: 300 000 ms (connect) / 600 000 ms (read).
* The request is built by `AnalyzeUrl`, not by `HttpHelper` — `HttpHelper` holds
  no TTS code at all.
* The JS bindings `speakText` and `speakSpeed` are available inside the request
  rule.
* `speakSpeed = speechRatePlay + 5` → **10** with the defaults.
* The audio is played with `MediaPlayer`/`ExoPlayer`.

### 1.6 Configuration

| Setting | Pref key | Default |
|---|---|---|
| `ttsFlowSys` | `ttsFollowSys` | true |
| `ttsSpeechRate` | `ttsSpeechRate` | 5 (`defaultSpeechRate`) |
| local TTS rate | — | `(ttsSpeechRate + 5) / 10f` → 1.0× |
| `ttsTimer` | `ttsTimer` | 0 (off) |
| `readAloudByPage` | `readAloudByPage` | false |
| `readAloudWakeLock` | `readAloudWakeLock` | false |
| `streamReadAloudAudio` | `streamReadAloudAudio` | false |
| `readAloudByMediaButton` | `readAloudByMediaButton` | false |
| `ignoreAudioFocus` | `ignoreAudioFocus` | false |
| `pauseReadAloudWhilePhoneCalls` | `pauseReadAloudWhilePhoneCalls` | false |
| `noAnimScrollPage` | `noAnimScrollPage` | false |
| — | `mediaButtonPerNext` | media buttons skip a chapter, not a paragraph |

`speechRatePlay = if (ttsFollowSys) defaultSpeechRate else ttsSpeechRate`.

---

## 2. Nine-zone tap mapping

### 2.1 The zones (`ui/book/read/page/ReadView.kt:130-140`)

```kotlin
private fun setRect9x() {
    tlRect.set(0f, 0f, width * 0.33f, height * 0.33f)
    tcRect.set(width * 0.33f, 0f, width * 0.66f, height * 0.33f)
    trRect.set(width * 0.36f, 0f, width.toFloat(), height * 0.33f)   // 0.36 — upstream bug
    mlRect.set(0f, height * 0.33f, width * 0.33f, height * 0.66f)
    mcRect.set(width * 0.33f, height * 0.33f, width * 0.66f, height * 0.66f)
    mrRect.set(width * 0.66f, height * 0.33f, width.toFloat(), height * 0.66f)
    blRect.set(0f, height * 0.66f, width * 0.33f, height.toFloat())
    bcRect.set(width * 0.33f, height * 0.66f, width * 0.66f, height.toFloat())
    brRect.set(width * 0.66f, height * 0.66f, width.toFloat(), height.toFloat())
}
```

* Thirds are **0.33 / 0.66**.
* `trRect` starts at **0.36**, so it overlaps `tcRect` in 0.36–0.66; because the
  dispatch tests `tc` before `tr`, a tap in that strip lands on **Top-Center**.
  The port reproduces this on purpose (documented quirk).
* `setRect9x()` runs on every size change (`onSizeChanged`).

### 2.2 Dispatch (`ReadView.kt:391-430`)

The tap uses the **ACTION_DOWN** coordinates (`startX`/`startY`), never the UP
coordinates. The order is

```
mc → bc → bl → br → ml → mr → tl → tc → tr
```

and the rects are inclusive of their edges, so the order resolves the ties.
Only the middle-center branch is guarded (`if (!isAbortAnim)`), i.e. while a
page-turn animation is being aborted the menu action is suppressed.
There is **no clamping** of the coordinates.

### 2.3 The click actions (`ReadView.kt:435-466`)

| id | action | effect |
|---|---|---|
| -1 | 不动作 | no branch in `click()` → no-op |
| 0 | 菜单 | dismiss the SnackBar + open the action menu |
| 1 | 下一页 | `pageDelegate?.nextPageByAnim(300)` |
| 2 | 上一页 | `pageDelegate?.prevPageByAnim(300)` |
| 3 | 下一章 | `ReadBook.moveToNextChapter(true)` |
| 4 | 上一章 | `ReadBook.moveToPrevChapter(upContent = true, toLast = false)` |
| 5 | 朗读上一段 | `ReadAloud.prevParagraph(context)` |
| 6 | 朗读下一段 | `ReadAloud.nextParagraph(context)` |
| 7 | 添加书签 | `callBack.addBookmark()` |
| 8 | 编辑内容 | show `ContentEditDialog` |
| 9 | 替换状态切换 | `callBack.changeReplaceRuleState()` |
| 10 | 目录 | `callBack.openChapterList()` |
| 11 | 搜索内容 | `callBack.openSearchActivity(null)` |
| 12 | 同步进度 | `ReadBook.syncProgress(...)` |
| 13 | 朗读暂停/继续 | `ReadAloud.pause` if playing, else `ReadAloud.resume` |

`showActionMenu()` (`ReadBookActivity.kt:1108-1115`) shows the read-aloud dialog
when the read-aloud service runs, the auto-page dialog when the auto pager runs,
the search menu when a search result is open, and the normal read menu
otherwise.

### 2.4 Defaults (`help/config/AppConfig.kt:30-38`)

| zone | default | meaning |
|---|---|---|
| Top-Left | 2 | previous page |
| Top-Center | 2 | previous page |
| Top-Right | 1 | next page |
| Middle-Left | 2 | previous page |
| Middle-Center | 0 | menu |
| Middle-Right | 1 | next page |
| Bottom-Left | 2 | previous page |
| Bottom-Center | 1 | next page |
| Bottom-Right | 1 | next page |

Pref keys (`constant/PreferKey.kt:19-27`): `clickActionTopLeft`,
`clickActionTopCenter`, `clickActionTopRight`, `clickActionMiddleLeft`,
`clickActionMiddleCenter`, `clickActionMiddleRight`, `clickActionBottomLeft`,
`clickActionBottomCenter`, `clickActionBottomRight`.

**Self-healing rule** (`AppConfig.kt:605-613`): if no zone is mapped to 0
(menu), the middle-center is reset to 0.

---

## 3. Page turning

### 3.1 The delegate API (`ui/book/read/page/delegate/PageDelegate.kt`)

There is **no** `onPageClick`; taps call `nextPageByAnim` / `prevPageByAnim`.

```
open    fun fling(startX, startY, velocityX, velocityY, minX, maxX, minY, maxY)
protected fun startScroll(startX, startY, dx, dy, animationSpeed)
protected fun stopScroll()
open    fun setViewSize(width, height)
open    fun computeScroll()
open    fun onScroll()
abstract fun abortAnim()
abstract fun onAnimStart(animationSpeed)
abstract fun onDraw(canvas)
abstract fun onAnimStop()
abstract fun nextPageByAnim(animationSpeed)
abstract fun prevPageByAnim(animationSpeed)
open    fun keyTurnPage(direction)
open    fun setDirection(direction)
abstract fun onTouch(event)
fun     onDown()
fun     hasPrev(): Boolean
fun     hasNext(): Boolean
fun     dismissSnackBar()
fun     postInvalidate()
open    fun onDestroy()
```

**Animation duration** (`PageDelegate.kt:72-82`):

```kotlin
val duration = if (dx != 0) (animationSpeed * abs(dx)) / viewWidth
               else (animationSpeed * abs(dy)) / viewHeight
```

`animationSpeed` = 300 for a tap, 100 for a keyboard page turn.

### 3.2 The delegate selection (`ReadView.kt:522-558`)

`PageAnim` (`constant/PageAnim.kt:8-16`): `coverPageAnim = 0`, `slidePageAnim = 1`,
`simulationPageAnim = 2`, `scrollPageAnim = 3`, `noAnim = 4`.
`ReadBook.pageAnim()` = the per-book override, else `ReadBookConfig.pageAnim`.

### 3.3 The drag detector (`HorizontalPageDelegate.kt:62-110`)

* The focal point is the **average of all pointers**.
* The movement threshold is the **squared** distance:
  `distance = deltaX² + deltaY² > pageSlopSquare2` where `pageSlopSquare2 =
  pageSlopSquare²` and `pageSlopSquare` is `AppConfig.pageTouchSlop` (default 0
  → the platform `scaledTouchSlop`).
* The direction is decided **purely by the drag direction**: right → PREV,
  left → NEXT. There is **no fling-velocity threshold**.
* `isCancel` means the finger reversed direction.

### 3.4 The animations

* **Cover** (`CoverPageDelegate.kt`) — the page is peeled back, the next page is
  revealed behind it, a 30 px wide shadow gradient is drawn along the fold.
* **Slide** (`SlidePageDelegate.kt`) — a plain horizontal slide, no shadow.
* **Simulation** (`SimulationPageDelegate.kt`) — a paper curl built from two
  quadratic Béziers; the current page is split into a front area (clipped out)
  and a back area (drawn with a mirrored colour matrix); the drag corner snaps
  to a page corner (`mCornerX`/`mCornerY`).
* **Scroll** (`ScrollPageDelegate.kt`) — continuous vertical scrolling; the
  velocity tracker window is 1000 ms; the fling bounds are ±10 × viewHeight;
  the next/previous page offsets are `-visibleHeight` for image pages and
  `-(lastLineTop - paddingTop)` otherwise.
* **No animation** (`NoAnimPageDelegate.kt`) — `fillPage(direction)` immediately.

### 3.5 Gestures

* **Long press = 600 ms** (`ReadView.kt:87-93`); cancelled when the finger moves
  past the platform slop. The selection expands to the whole paragraph and then
  snaps to word boundaries with `java.text.BreakIterator`.
* While a selection is active a tap cancels the selection instead of running a
  zone action.
* `defaultAnimationSpeed = 300` (`ReadView.kt:68`).

---

## 4. What the port implements

* `Sources/LegadoCore/Reader/ReaderInteraction.swift` — the tap zones, the
  click actions, the dispatch order, the defaults and the self-healing rule.
* `Sources/LegadoCore/Reader/ReadAloud.swift` — the paragraph splitting, the
  skipped-paragraph rule, the chapter offset → page mapping and the HTTP TTS
  request building.
* The SwiftUI layer maps the gestures onto these primitives; the Android
  canvas animations are not reproduced (the port uses the system page
  transition).
