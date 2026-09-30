import AppKit
import Carbon.HIToolbox
import Foundation

/// Which key holds the mic open (or, for Command Mode, listens for an instruction).
///
/// Two families: **modifier keys**, tracked through `flagsChanged` with device-specific
/// left/right masks, and **function keys F1–F19**, tracked through `keyDown`/`keyUp`.
/// Ordinary character keys are deliberately not offered: holding one to talk would type
/// it, or have to be swallowed, in every app.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption, leftOption, rightCommand, leftCommand
    case rightControl, leftControl, rightShift, leftShift, fn
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)     // 61
        case .leftOption: Int64(kVK_Option)           // 58
        case .rightCommand: Int64(kVK_RightCommand)   // 54
        case .leftCommand: Int64(kVK_Command)         // 55
        case .rightControl: Int64(kVK_RightControl)   // 62
        case .leftControl: Int64(kVK_Control)         // 59
        case .rightShift: Int64(kVK_RightShift)       // 60
        case .leftShift: Int64(kVK_Shift)             // 56
        case .fn: Int64(kVK_Function)                 // 63
        case .f1: Int64(kVK_F1); case .f2: Int64(kVK_F2); case .f3: Int64(kVK_F3); case .f4: Int64(kVK_F4)
        case .f5: Int64(kVK_F5); case .f6: Int64(kVK_F6); case .f7: Int64(kVK_F7); case .f8: Int64(kVK_F8)
        case .f9: Int64(kVK_F9); case .f10: Int64(kVK_F10); case .f11: Int64(kVK_F11); case .f12: Int64(kVK_F12)
        case .f13: Int64(kVK_F13); case .f14: Int64(kVK_F14); case .f15: Int64(kVK_F15); case .f16: Int64(kVK_F16)
        case .f17: Int64(kVK_F17); case .f18: Int64(kVK_F18); case .f19: Int64(kVK_F19)
        }
    }

    /// The key as the keyboard reported it, or nil when the code isn't one we offer.
    init?(keyCode: Int64) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = match
    }

    var isModifier: Bool { flag != nil }

    /// Device-*dependent* bit for this specific physical modifier key; nil for F keys.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so `onRelease` never fires. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags? {
        switch self {
        case .leftControl: CGEventFlags(rawValue: 0x01)   // NX_DEVICELCTLKEYMASK
        case .leftShift: CGEventFlags(rawValue: 0x02)     // NX_DEVICELSHIFTKEYMASK
        case .rightShift: CGEventFlags(rawValue: 0x04)    // NX_DEVICERSHIFTKEYMASK
        case .leftCommand: CGEventFlags(rawValue: 0x08)   // NX_DEVICELCMDKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .leftOption: CGEventFlags(rawValue: 0x20)    // NX_DEVICELALTKEYMASK
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightControl: CGEventFlags(rawValue: 0x2000) // NX_DEVICERCTLKEYMASK
        case .fn: .maskSecondaryFn                         // no left/right variant exists
        default: nil
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .leftOption: "Left ⌥"
        case .rightCommand: "Right ⌘"
        case .leftCommand: "Left ⌘"
        case .rightControl: "Right ⌃"
        case .leftControl: "Left ⌃"
        case .rightShift: "Right ⇧"
        case .leftShift: "Left ⇧"
        case .fn: "fn"
        default: rawValue.uppercased()  // "F5"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so we let it
    /// through. Dedicated right-hand modifiers and F keys are safe to consume; the left
    /// modifiers are passed through because they anchor every ordinary shortcut.
    var shouldConsumeEvent: Bool {
        switch self {
        case .fn, .leftOption, .leftCommand, .leftControl, .leftShift: false
        default: true
        }
    }
}

/// Watches for a held modifier key using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
@MainActor
final class HotkeyMonitor {
    /// One held key and what it does. Dictation and Command Mode are two of these on
    /// different keys; the tap itself doesn't know which is which.
    struct Binding {
        let key: PushToTalkKey
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressed: Set<PushToTalkKey> = []

    var bindings: [Binding] = []
    var onCancel: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.bindings.map(\.key.displayName).joined(separator: ", "))")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        pressed = []
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        if type == .keyDown, keyCode == 53 { onCancel?(); return false }
        guard let binding = bindings.first(where: { $0.key.keyCode == keyCode }) else { return false }

        let key = binding.key
        let nowPressed: Bool
        if let flag = key.flag {
            guard type == .flagsChanged else { return false }
            nowPressed = flags.contains(flag)
        } else {
            // F keys: down/up events. Autorepeat re-sends keyDown while held; ignore it.
            switch type {
            case .keyDown: if isRepeat { return key.shouldConsumeEvent }; nowPressed = true
            case .keyUp: nowPressed = false
            default: return false
            }
        }
        guard nowPressed != pressed.contains(key) else { return key.shouldConsumeEvent }
        if nowPressed { pressed.insert(key) } else { pressed.remove(key) }

        if nowPressed { binding.onPress() } else { binding.onRelease() }

        return key.shouldConsumeEvent
    }
}
