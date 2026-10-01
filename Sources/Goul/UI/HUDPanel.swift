import AppKit
import SwiftUI

/// The floating capsule that appears while you hold the key.
///
/// The single most important property here is that this panel **never becomes key**.
/// If it did, the user's text field would lose focus and `TextInjector` would have
/// nothing to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false`.
@MainActor
final class HUDPanel: NSPanel {
    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: GoulTheme.HUD.windowWidth, height: GoulTheme.HUD.windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        // Overlay semantics: on every Space (including full-screen ones), never part of
        // Mission Control or ⌘-tab cycling. `.stationary` used to be in this set and was
        // dropped: combined with `.canJoinAllSpaces` the panel stayed bound to the Space
        // it was first shown on, so dictation on another desktop had sound but no HUD.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: HUDView(controller: controller))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Parks the pill just above the Dock, horizontally centered on the active screen.
    ///
    /// The window is taller than the pill (room for Brook and the shadow), so the pill's
    /// own bottom edge — not the window's — is what sits `dockGap` above the Dock.
    ///
    /// `NSScreen.main` is the screen with the *key window* — and an accessory app with a
    /// non-activating panel never has one, so it can be nil. Falling back to `screens.first`
    /// keeps the HUD on-screen instead of stranding it at the origin.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + GoulTheme.HUD.dockGap - GoulTheme.HUD.margin
            )
        )
    }

    func present() {
        // Every active state change (starting → listening → finishing) calls this. Always
        // reposition and re-order — that is what brings the panel onto the current Space
        // — but only fade in when it was actually hidden, or it flickers mid-utterance.
        let wasShowing = isVisible && alphaValue >= 1
        reposition()
        if !wasShowing { alphaValue = 0 }
        orderFrontRegardless()
        Log.app.info("hud: present at \(NSStringFromRect(self.frame), privacy: .public) onActiveSpace=\(self.isOnActiveSpace) visible=\(self.isVisible) wasShowing=\(wasShowing)")
        guard !wasShowing else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        Log.app.info("hud: dismiss visible=\(self.isVisible)")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit always calls this on the main thread.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
