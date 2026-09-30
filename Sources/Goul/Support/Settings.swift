import AppKit
import Foundation
import Observation
import SwiftUI

/// How the HUD pill is drawn. Chosen in Settings → Floating pill.
enum HUDGlassStyle: String, CaseIterable, Sendable {
    /// Opaque colour with the ocean hairline — the original Goul look, and the default.
    case solid
    /// Liquid Glass tinted with the chosen colour.
    case tinted
    /// Liquid Glass exactly as macOS renders it: no tint, no fill, no hairline.
    case native
}

/// Both engines detect English and French automatically; this only picks the model.
///
/// Apple Speech is the default: in real use (2026-09-30) it handled fast French clearly
/// better than Parakeet v3 int8, and it shows live text. It gets automatic detection by
/// running two locked recognisers at once (`AutoLanguageAppleEngine`). Parakeet v3 is
/// natively multilingual, so detection there costs nothing, but its French lagged.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple, parakeet
    var displayName: String { self == .apple ? "Apple Speech" : "Parakeet v3" }
    var showsLiveText: Bool { self == .apple }
}
@MainActor @Observable
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    var pushToTalkKey: PushToTalkKey { didSet { defaults.set(pushToTalkKey.rawValue, forKey: "pushToTalkKey") } }
    /// Command Mode: hold this key, say what to do with the selected text, release.
    var commandKey: PushToTalkKey { didSet { defaults.set(commandKey.rawValue, forKey: "commandKey") } }
    var commandModeEnabled: Bool { didSet { defaults.set(commandModeEnabled, forKey: "commandModeEnabled") } }
    var engine: SpeechEngineChoice { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    var cleanupEnabled: Bool { didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    /// Show the running transcript in the HUD pill. Off: the pill is a small instrument only.
    var liveTextEnabled: Bool { didSet { defaults.set(liveTextEnabled, forKey: "liveTextEnabled") } }
    var hudGlassStyle: HUDGlassStyle { didSet { defaults.set(hudGlassStyle.rawValue, forKey: "hudGlassStyle") } }
    /// Tint laid over the glass when the style is `.tinted`. Stored as sRGB components.
    var hudTintColor: Color {
        didSet {
            let c = NSColor(hudTintColor).usingColorSpace(.sRGB) ?? .black
            defaults.set([c.redComponent, c.greenComponent, c.blueComponent], forKey: "hudTintRGB")
        }
    }
    /// 0…1, how much of the tint shows through. Low values are nearly pure glass.
    var hudTintStrength: Double { didSet { defaults.set(hudTintStrength, forKey: "hudTintStrength") } }
    var hudOutline: Bool { didSet { defaults.set(hudOutline, forKey: "hudOutline") } }
    var hudMascotEnabled: Bool { didSet { defaults.set(hudMascotEnabled, forKey: "hudMascotEnabled") } }


    var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: "historyEnabled")
            RunLog.persistenceChanged(enabled: historyEnabled)
        }
    }
    private init() {
        pushToTalkKey = PushToTalkKey(rawValue: defaults.string(forKey: "pushToTalkKey") ?? "") ?? .rightOption
        commandKey = PushToTalkKey(rawValue: defaults.string(forKey: "commandKey") ?? "") ?? .rightCommand
        commandModeEnabled = defaults.object(forKey: "commandModeEnabled") as? Bool ?? true
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: "engine") ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? false
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        liveTextEnabled = defaults.object(forKey: "liveTextEnabled") as? Bool ?? false
        hudGlassStyle = HUDGlassStyle(rawValue: defaults.string(forKey: "hudGlassStyle") ?? "") ?? .solid
        if let rgb = defaults.array(forKey: "hudTintRGB") as? [Double], rgb.count == 3 {
            hudTintColor = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        } else {
            hudTintColor = GoulTheme.HUD.defaultTint
        }
        hudTintStrength = defaults.object(forKey: "hudTintStrength") as? Double ?? GoulTheme.HUD.defaultTintStrength
        hudOutline = defaults.object(forKey: "hudOutline") as? Bool ?? true
        hudMascotEnabled = defaults.object(forKey: "hudMascotEnabled") as? Bool ?? true
        historyEnabled = defaults.object(forKey: "historyEnabled") as? Bool ?? false
    }
}
