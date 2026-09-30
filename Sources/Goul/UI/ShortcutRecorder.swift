import AppKit
import SwiftUI

/// "Change…", then press the key you want. Accepts modifier keys (left and right) , fn,
/// and F1–F19; refuses character keys with an explanation. Escape cancels.
///
/// Uses a local `NSEvent` monitor: the Settings window is key while recording, so no
/// Accessibility is needed, and the global tap is paused so the press can't start a
/// dictation.
struct ShortcutRecorder: View {
    let title: String
    @Binding var key: PushToTalkKey
    /// The other binding, so the two shortcuts can't be set to the same key.
    var conflictsWith: PushToTalkKey?
    let controller: DictationController

    @State private var recording = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(spacing: DS.Space.base) {
                Text(title)
                Spacer()
                Text(recording ? "Press a key…" : key.displayName)
                    .font(GoulTheme.caption).fontWeight(.semibold)
                    .foregroundStyle(recording ? GoulTheme.red : GoulTheme.ink)
                    .padding(.horizontal, DS.Space.base).padding(.vertical, DS.Space.snug)
                    .background(Color.white.opacity(0.35), in: .rect(cornerRadius: DS.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(recording ? GoulTheme.red : GoulTheme.line.opacity(0.7)))
                Button(recording ? "Cancel" : "Change…") { recording ? stop() : start() }
                    .buttonStyle(GoulButtonStyle())
            }
            if let hint {
                Text(hint).font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        controller.pauseHotkey()
        recording = true
        hint = "Modifier keys (⌥ ⌘ ⌃ ⇧, left or right), fn, or F1–F19. Escape to keep \(key.displayName)."
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event)
            return nil  // swallow: the press configures, it doesn't type
        }
    }

    private func handle(_ event: NSEvent) {
        let code = Int64(event.keyCode)
        if event.type == .keyDown, code == 53 { stop(); return }  // Escape
        // flagsChanged fires on release too; only act on the press.
        if event.type == .flagsChanged, let candidate = PushToTalkKey(keyCode: code),
           let flag = candidate.flag, !CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).contains(flag) {
            return
        }
        guard let candidate = PushToTalkKey(keyCode: code) else {
            if event.type == .keyDown {
                hint = "That key would type in other apps. Use a modifier key, fn, or an F key."
            }
            return
        }
        guard candidate != conflictsWith else {
            hint = "\(candidate.displayName) is already the other shortcut. Pick a different key."
            return
        }
        key = candidate
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        hint = nil
        controller.reloadHotkey()
    }
}
