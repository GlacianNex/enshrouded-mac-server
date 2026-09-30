import AppKit
import SwiftUI

/// Fit short setup forms and progress states; long content remains scrollable.
struct ContentFittingWindow: NSViewRepresentable {
    let contentHeight: CGFloat
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) { view.fit(contentHeight) }

    final class SizingView: NSView {
        private var contentHeight: CGFloat = 0
        private var appliedHeight: CGFloat?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); fit(contentHeight) }
        func fit(_ height: CGFloat) {
            contentHeight = height
            guard height > 0, let window else { return }
            let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            let target = ceil(min(max(height, 200), available - 100))
            guard appliedHeight != target else { return }
            appliedHeight = target
            window.contentMinSize = NSSize(width: 550, height: min(target, 300))
            var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.contentLayoutRect.width, height: target))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
    }
}
