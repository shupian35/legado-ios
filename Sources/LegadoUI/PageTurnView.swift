#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The page view of the reader.
///
/// The upstream draws the five page-turn styles on an Android `Canvas`
/// (`ui/book/read/page/delegate/*`):
/// - `slide` — the revealed page slides in while the current page slides out
///   (upstream `SlidePageDelegate`),
/// - `cover` — the current page slides over the revealed page, which stays in
///   place, with a shadow along the leading edge (upstream
///   `CoverPageDelegate`),
/// - `simulation` — the current page is folded back around its edge (upstream
///   `SimulationPageDelegate`; the port folds it around the vertical edge
///   instead of the upstream's diagonal Bézier, because SwiftUI has no
///   equivalent of the upstream's canvas clipping),
/// - `scroll` — a continuous vertical scroll,
/// - `none` — an instant swap.
///
/// The transforms themselves are computed by `PageTurnLayout` in the engine,
/// so they can be tested without a UI.
public struct PageTurnView: View {

    /// The laid-out lines of the page.
    public var lines: [TextLine]
    /// The laid-out lines of the page that is revealed by the turn — the next
    /// page when the page is turned forward, the previous page otherwise.
    public var revealedLines: [TextLine]
    /// The font of the title lines.
    public var titleFont: Font
    /// The font of the body lines.
    public var bodyFont: Font
    /// The style of the turn.
    public var style: PageTurnStyle
    /// The direction of the current turn.
    public var direction: PageTurnDirection
    /// The colour of the text — upstream `ReadBookConfig.curTextColor`.
    public var textColor: Color
    /// The fraction of the drag that has been travelled (0…1).
    public var progress: Double
    /// The width of the reader view.
    public var viewWidth: Double

    public init(
        lines: [TextLine],
        revealedLines: [TextLine] = [],
        titleFont: Font = .system(size: 17),
        bodyFont: Font = .system(size: 17),
        style: PageTurnStyle = .slide,
        direction: PageTurnDirection = .next,
        textColor: Color = .primary,
        progress: Double = 0,
        viewWidth: Double = 0
    ) {
        self.lines = lines
        self.revealedLines = revealedLines
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.style = style
        self.direction = direction
        self.textColor = textColor
        self.progress = progress
        self.viewWidth = viewWidth
    }

    /// The transforms of the turn — upstream `PageDelegate.onDraw`.
    private var layout: PageTurnLayout {
        PageTurnLayout(
            style: style,
            direction: direction,
            progress: progress,
            viewWidth: viewWidth
        )
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: lines.count)
    }

    @ViewBuilder
    private var content: some View {
        if style == .scroll {
            ScrollView {
                page(lines: lines)
            }
        } else {
            ZStack(alignment: .topLeading) {
                if layout.drawsRevealedPage, !revealedLines.isEmpty {
                    // The page that is revealed by the turn — upstream draws it
                    // under the page that is turned away.
                    page(lines: revealedLines)
                        .offset(x: layout.revealedOffsetX)
                }
                page(lines: lines)
                    .offset(x: layout.currentOffsetX)
                    .rotation3DEffect(
                        .degrees(layout.rotationDegrees),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: layout.hinge == .leading ? .leading : .trailing
                    )
                    .shadow(
                        color: Color.black.opacity(0.35),
                        radius: 6,
                        x: layout.hinge == .leading ? 4 : -4
                    )
            }
        }
    }

    private func page(lines: [TextLine]) -> some View {
        PagedContentView(
            lines: lines,
            titleFont: titleFont,
            bodyFont: bodyFont,
            textColor: textColor
        )
    }
}

/// The reader area with the drag gesture — the horizontal page delegate.
public struct PageTurnContainer<Content: View>: View {

    /// The style of the turn.
    public var style: PageTurnStyle
    /// The width of the view.
    public var viewWidth: Double
    /// The action run when the page turns.
    public var onTurn: (PageTurnDirection) -> Void
    /// The action run while the page is dragged — the fraction of the turn
    /// that has been travelled (0…1).
    ///
    /// The upstream binds the drag progress to the page delegate
    /// (`PageDelegate.startScroll` → the canvas is redrawn with the offset);
    /// without it the page only swaps at the end of the drag.
    public var onProgress: (Double) -> Void
    /// The action run when the direction of the drag is known — the reader
    /// draws the page that is revealed by the turn.
    public var onDirection: (PageTurnDirection) -> Void
    /// The content.
    public var content: Content

    @State private var session = PageTurnSession()

    public init(
        style: PageTurnStyle = .slide,
        viewWidth: Double = 400,
        onTurn: @escaping (PageTurnDirection) -> Void = { _ in },
        onProgress: @escaping (Double) -> Void = { _ in },
        onDirection: @escaping (PageTurnDirection) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.viewWidth = viewWidth
        self.onTurn = onTurn
        self.onProgress = onProgress
        self.onDirection = onDirection
        self.content = content()
    }

    public var body: some View {
        content
            .gesture(drag)
    }

    private var drag: DragGestureModifier {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                session.style = style
                if session.startPoint == nil {
                    session.begin(at: CGPointLike(x: Double(value.startLocation.x), y: Double(value.startLocation.y)))
                }
                session.update(
                    pointers: [CGPointLike(x: Double(value.location.x), y: Double(value.location.y))],
                    viewWidth: viewWidth
                )
                // The direction of the drag decides which page is revealed —
                // upstream `HorizontalPageDelegate.setDirection`.
                if case let .turn(direction) = session.decision {
                    onDirection(direction)
                }
                onProgress(session.progress(viewWidth: viewWidth))
            }
            .onEnded { _ in
                onProgress(0)
                if case let .turn(direction) = session.end() {
                    onTurn(direction)
                }
            }
    }
}
