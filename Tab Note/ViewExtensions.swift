//
//  ViewExtensions.swift
//  Tab Note
//

import SwiftUI
import AppKit

extension View {
    /// Conditionally apply a modifier — used by AIPopupView to skip background when embedded in popover.
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    /// Prevents the NSPanel's isMovableByWindowBackground from swallowing drags on this view.
    /// Apply this to any SwiftUI view (e.g. a tab pill) that needs its own drag gesture.
    func nonMovableWindow() -> some View {
        self.background(NonMovableWindowView())
    }
}

// MARK: - NonMovableWindowView

/// A transparent NSView that explicitly opts out of window-background dragging.
/// When placed behind a SwiftUI view inside a panel with isMovableByWindowBackground = true,
/// it prevents that region from being used to move the window — so SwiftUI .onDrag works.
private struct NonMovableWindowView: NSViewRepresentable {
    func makeNSView(context: Context) -> _NonMovableNSView { _NonMovableNSView() }
    func updateNSView(_ nsView: _NonMovableNSView, context: Context) {}
}

final class _NonMovableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // pass all events through to SwiftUI
}

// MARK: - ScreenFrameReporter

/// Reports this view's bounds converted to screen coordinates.
struct ScreenFrameReporter: NSViewRepresentable {
    var onFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> _ScreenFrameReporterView {
        let view = _ScreenFrameReporterView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: _ScreenFrameReporterView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrame()
    }
}

final class _ScreenFrameReporterView: NSView {
    var onFrameChange: ((CGRect) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportFrame()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        reportFrame()
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    func reportFrame() {
        guard let window = window else { return }
        let windowRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        onFrameChange?(screenRect)
    }
}
