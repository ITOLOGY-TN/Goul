import AppKit
import ApplicationServices
import GoulCore

@MainActor
enum TextInjector {
    struct Target {
        let pid: pid_t
        let appName: String
        /// The focused AX element at key-down, when the app exposes one. Terminals,
        /// Electron apps and some web views don't, or hand back a fresh object on every
        /// call — so this is a hint for logging, not a gate. The gate is the app (`pid`)
        /// plus "not a password field".
        let element: AXUIElement?
    }
    static func captureTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            Log.app.info("inject: no frontmost app at key-down"); return nil
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            Log.app.info("inject: Goul itself is frontmost — nothing to insert into"); return nil
        }
        let element = focusedElement()
        if let element, isSecure(element) {
            Log.app.info("inject: focused field is secure — refusing"); return nil
        }
        let name = app.localizedName ?? "pid \(app.processIdentifier)"
        Log.app.info("inject: target \(name, privacy: .public), focused element \(element == nil ? "unavailable" : "captured", privacy: .public)")
        return Target(pid: app.processIdentifier, appName: name, element: element)
    }
    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private static func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        return (value as? String) == "AXSecureTextField"
    }
    /// Still the same app, and not now sitting in a password field.
    private static func matches(_ target: Target) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            Log.app.info("inject: frontmost app changed since key-down — not inserting"); return false
        }
        let current = focusedElement()
        if let current, isSecure(current) {
            Log.app.info("inject: focus moved to a secure field — not inserting"); return false
        }
        if let current, let original = target.element, !CFEqual(current, original) {
            Log.app.info("inject: focused element differs from key-down (same app; proceeding)")
        }
        return true
    }
    /// The text currently selected in `target`, for Command Mode. Nil when nothing is.
    ///
    /// Asks Accessibility first, which leaves the selection untouched. Apps that don't
    /// expose it (terminals, most Electron apps) get a synthetic ⌘C with the pasteboard
    /// saved and restored around it; the selection itself survives a copy, which is what
    /// lets the eventual paste replace it.
    static func captureSelection(in target: Target) async -> String? {
        if let element = target.element {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                Log.app.info("command: selection via Accessibility (\(text.count) chars)")
                return text
            }
        }
        let board = NSPasteboard.general
        let saved = snapshot(board)
        let before = board.changeCount
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        for _ in 0..<10 where board.changeCount == before {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard board.changeCount != before else {
            Log.app.info("command: no selection (⌘C changed nothing)")
            return nil
        }
        let copied = board.string(forType: .string)
        restore(saved, board: board, written: board.changeCount)
        Log.app.info("command: selection via ⌘C (\(copied?.count ?? 0) chars)")
        return copied.flatMap { $0.isEmpty ? nil : $0 }
    }
    static func insert(_ text: String, into target: Target) async -> Bool {
        guard !text.isEmpty, !Task.isCancelled else { return false }
        guard AXIsProcessTrusted() else { Log.app.error("inject: not trusted for Accessibility"); return false }
        guard matches(target) else { return false }
        // Wait for the *physical* modifiers to be released before synthesizing ⌘V, so the
        // paste doesn't turn into ⌥⌘V or ⇧⌘V.
        //
        // `.hidSystemState` on purpose, not `.combinedSessionState`. The combined state
        // also folds in synthetic events — including our own ⌘V — and was observed keeping
        // ⌘ "held" long after the previous insertion, so every second dictation timed out
        // here and silently dropped its text. The HID state is what the keyboard actually
        // reports.
        for _ in 0..<40 {
            if Self.heldModifiers().isEmpty { break }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        let held = Self.heldModifiers()
        guard held.isEmpty else {
            Log.app.info("inject: modifiers still physically held after 2s (\(held.rawValue)) — not inserting"); return false
        }
        guard !Task.isCancelled, matches(target) else { return false }
        let board = NSPasteboard.general
        let saved = snapshot(board)
        board.clearContents()
        guard board.setString(text, forType: .string) else { Log.app.error("inject: pasteboard write failed"); return false }
        let written = board.changeCount
        do { try await Task.sleep(for: .milliseconds(40)) } catch {
            restore(saved, board: board, written: written)
            return false
        }
        guard !Task.isCancelled, matches(target), ClipboardOwnership.canRestore(written: written, current: board.changeCount),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            Log.app.info("inject: pasteboard changed or target lost before ⌘V — not inserting")
            restore(saved, board: board, written: written)
            return false
        }
        Log.app.info("inject: ⌘V into \(target.appName, privacy: .public) (\(text.count) chars)")
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            restore(saved, board: board, written: written)
        }
        return true
    }
    private static func snapshot(_ board: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        board.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        } ?? []
    }
    private static func heldModifiers() -> CGEventFlags {
        CGEventSource.flagsState(.hidSystemState)
            .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
    }
    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], board: NSPasteboard, written: Int) {
        guard ClipboardOwnership.canRestore(written: written, current: board.changeCount) else { return }
        board.clearContents()
        board.writeObjects(saved.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        })
    }
}
