#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The page view of the reader.
///
/// The upstream draws the five page-turn styles on an Android `Canvas`
/// (`ui/book/read/page/delegate/*`). On iOS the same behaviour is expressed
/// with the SwiftUI transitions:
/// - `slide` — a horizontal slide,
/// - `cover` — a 3D flip (the closest analogue of the peeled page),
/// - `simulation` — a 3D flip with a shadow (the paper curl),
/// - `scroll` — a continuous vertical scroll,
/// - `none` — an instant swap.
public struct PageTurnView: View {

    /// The laid-out lines of the page.
    public var lines: [TextLine]
    /// The font of the title lines.
    public var titleFont: Font
    /// The font of the body lines.
    public var bodyFont: Font
    /// The style of the turn.
    public var style: PageTurnStyle
    /// The direction of the current turn.
    public var direction: PageTurnDirection
    /// The fraction of the drag that has been travelled (0…1).
    public var progress: Double

    public init(
        lines: [TextLine],
        titleFont: Font = .system(size: 17),
        bodyFont: Font = .system(size: 17),
        style: PageTurnStyle = .slide,
        direction: PageTurnDirection = .next,
        progress: Double = 0
    ) {
        self.lines = lines
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.style = style
        self.direction = direction
        self.progress = progress
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .offset(x: offsetX)
            .offset(y: offsetY)
            .rotation3DEffect(.degrees(rotationAngle), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.2), value: lines.count)
    }

    @ViewBuilder
    private var content: some View {
        if style == .scroll {
            ScrollView {
                page
            }
        } else {
            page
        }
    }

    private var page: some View {
        PagedContentView(
            lines: lines,
            titleFont: titleFont,
            bodyFont: bodyFont
        )
    }

    private var offsetX: Double {
        switch style {
        case .slide, .cover, .simulation:
            return direction == .next ? -progress * 120 : progress * 120
        case .scroll, .none:
            return 0
        }
    }

    private var offsetY: Double {
        switch style {
        case .scroll:
            return direction == .next ? -progress * 120 : progress * 120
        case .cover, .slide, .simulation, .none:
            return 0
        }
    }

    private var rotationAngle: Double {
        switch style {
        case .cover, .simulation:
            return direction == .next ? -progress * 60 : progress * 60
        case .slide, .scroll, .none:
            return 0
        }
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
    /// The content.
    public var content: Content

    @State private var session = PageTurnSession()

    public init(
        style: PageTurnStyle = .slide,
        viewWidth: Double = 400,
        onTurn: @escaping (PageTurnDirection) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.viewWidth = viewWidth
        self.onTurn = onTurn
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
            }
            .onEnded { _ in
                if case let .turn(direction) = session.end() {
                    onTurn(direction)
                }
            }
    }
}
