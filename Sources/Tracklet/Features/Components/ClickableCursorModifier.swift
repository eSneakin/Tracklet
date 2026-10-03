import AppKit
import SwiftUI

struct ClickableCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            CursorTrackingView(cursor: isEnabled ? .pointingHand : .arrow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension View {
    func trackletClickableCursor() -> some View {
        modifier(ClickableCursorModifier())
    }
}

private struct CursorTrackingView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorTrackingNSView {
        CursorTrackingNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorTrackingNSView, context: Context) {
        nsView.cursor = cursor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CursorTrackingNSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

private final class CursorTrackingNSView: NSView {
    var cursor: NSCursor
    private var cursorTrackingArea: NSTrackingArea?

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // Observe pointer movement without intercepting the underlying SwiftUI button's clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { applyCursor() }
    override func mouseMoved(with event: NSEvent) { applyCursor() }
    override func cursorUpdate(with event: NSEvent) { applyCursor() }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { NSCursor.arrow.set() }
    }

    private func applyCursor() {
        let cursor = cursor
        // AppKit/SwiftUI can reset the cursor during the current event; apply after dispatch.
        DispatchQueue.main.async { cursor.set() }
    }
}
