import AppKit
import SwiftUI

/// Settings, organised as sections: a list on the left, one section's controls on the
/// right. Shown both inside the main window's Settings tab and in the ⌘, window.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var section: SettingsSection
    /// Off only for the off-screen snapshots: `ImageRenderer` gives a `ScrollView` no size.
    private let scrolls: Bool
    /// Inside an illustrated theme's panel the artwork is the background.
    private let transparent: Bool
    @State private var themes = ThemeManager.shared

    init(controller: DictationController, section: SettingsSection = .shortcuts, scrolls: Bool = true, transparent: Bool = false) {
        self.controller = controller
        _section = State(initialValue: section)
        self.scrolls = scrolls
        self.transparent = transparent
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case shortcuts = "Shortcuts"
        case speech = "Speech"
        case appearance = "Appearance"
        case privacy = "Privacy & data"
        case permissions = "Permissions"
        case about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .shortcuts: "keyboard"
            case .speech: "waveform"
            case .appearance: "paintbrush"
            case .privacy: "lock.shield"
            case .permissions: "checkmark.shield"
            case .about: "info.circle"
            }
        }
        var blurb: String {
            switch self {
            case .shortcuts: "The keys you hold to dictate and to command."
            case .speech: "Which local model listens, and how the text is cleaned."
            case .appearance: "The floating pill, Brook, and live text."
            case .privacy: "What Goul keeps on this Mac. Audio is never saved."
            case .permissions: "The two macOS grants Goul cannot work without."
            case .about: "Goul, personal edition."
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(GoulTheme.line)
            if scrolls { ScrollView { detail } } else { detail }
        }
        .background(transparent ? Color.clear : GoulTheme.paper).foregroundStyle(GoulTheme.ink).preferredColorScheme(.light)
    }

    private var detail: some View {
                VStack(alignment: .leading, spacing: DS.Space.wide) {
                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text(section.rawValue).font(GoulTheme.title)
                        Text(section.blurb).font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                    }
                    switch section {
                    case .shortcuts: shortcuts
                    case .speech: speech
                    case .appearance: appearance
                    case .privacy: privacy
                    case .permissions: permissions
                    case .about: about
                    }
                }
                .font(GoulTheme.body).padding(GoulTheme.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Navigation

    private var rail: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            ForEach(SettingsSection.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: DS.Space.snug) {
                        Image(systemName: item.symbol).frame(width: DS.Space.roomy)
                        Text(item.rawValue)
                        Spacer(minLength: 0)
                    }
                    .font(GoulTheme.body)
                    .foregroundStyle(section == item ? GoulTheme.paper : GoulTheme.ink)
                    .padding(.horizontal, DS.Space.base).padding(.vertical, DS.Space.snug)
                    .background(section == item ? GoulTheme.ocean : .clear, in: .rect(cornerRadius: DS.Radius.control))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(DS.Space.base)
        .frame(width: GoulTheme.settingsRail, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(transparent ? Color.clear : GoulTheme.paper.opacity(0.6))
    }

    // MARK: - Sections

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            group("Dictation") {
                ShortcutRecorder(title: "Hold this key to dictate", key: $settings.pushToTalkKey,
                                 conflictsWith: settings.commandModeEnabled ? settings.commandKey : nil, controller: controller)
                note("Hold in another app to dictate. Release to insert. Escape cancels, including during the short review moment after you release. Right-hand modifiers and F keys are swallowed while held; left-hand modifiers and fn pass through so your other shortcuts keep working.")
            }
            group("Command mode") {
                Toggle("Rewrite selected text by voice", isOn: $settings.commandModeEnabled)
                    .onChange(of: settings.commandModeEnabled) { _, _ in controller.reloadHotkey() }
                ShortcutRecorder(title: "Hold this key to command", key: $settings.commandKey,
                                 conflictsWith: settings.pushToTalkKey, controller: controller)
                    .disabled(!settings.commandModeEnabled)
                if settings.commandKey == settings.pushToTalkKey {
                    note("Same key as dictation — Command mode is off until you pick a different one.")
                }
                note(CommandRewriter.isAvailable
                    ? "Select text in any app, hold the key, say “make this more formal” or “translate to English”, release. With nothing selected, “write a reply saying I’ll be late” inserts the text. Runs on Apple Intelligence, on this Mac only."
                    : (CommandRewriter.unavailableReason ?? "Needs Apple Intelligence."))
            }
        }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            group("Engine") {
                Picker("On-device engine", selection: $settings.engine) {
                    ForEach(SpeechEngineChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.disabled(controller.state.isActive || controller.isPreparing)
                note(settings.engine == .apple
                    ? "Recommended. Apple's local model, live text while you speak. English and French run side by side and Goul keeps the one you spoke. Both language packs download once."
                    : "Multilingual Parakeet v3 on your Mac hears English and French without a switch; text appears on release. One model download (~470 MB), then fully offline. Weaker on fast French.")
                Button(controller.isPreparing ? "Preparing…" : "Prepare selected engine") { controller.prepare() }
                    .buttonStyle(GoulButtonStyle()).disabled(controller.isPreparing || controller.state.isActive)
                if !controller.setupMessage.isEmpty { note(controller.setupMessage) }
            }
            group("Language") {
                Label("English and French, detected automatically", systemImage: "globe")
                note("There is nothing to choose. Each dictation is transcribed in the language you spoke; the pill and the log show EN or FR.")
            }
            group("Cleanup") {
                Toggle("Clean up fillers and punctuation", isOn: $settings.cleanupEnabled)
                note(FoundationModelFormatter.isAvailable
                    ? "Apple Intelligence on this Mac fixes punctuation, capitals and self-corrections in the detected language, adding about a second. Falls back to simple rules if it changes your meaning."
                    : "Simple rules in the detected language: “um” and “new line” in English, “euh” and “à la ligne” in French. \(FoundationModelFormatter.unavailableReason ?? "")")
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            group("Theme") {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Space.base) {
                        ForEach(themes.themes) { theme in ThemeCard(theme: theme, selected: theme == themes.current) { themes.select(theme.id) } }
                    }.padding(DS.Space.hair)
                }
                note("Generated theme packs live in Resources/Themes/<slug>/ — see docs/THEME-ASSET-PROMPT.md. The logbook theme needs no files. Applies immediately.")
            }
            group("Floating pill") {
                Picker("Style", selection: $settings.hudGlassStyle) {
                    Text("Solid colour").tag(HUDGlassStyle.solid)
                    Text("Tinted Liquid Glass").tag(HUDGlassStyle.tinted)
                    Text("Native Liquid Glass").tag(HUDGlassStyle.native)
                }
                if settings.hudGlassStyle != .native {
                    ColorPicker("Colour", selection: $settings.hudTintColor, supportsOpacity: false)
                }
                if settings.hudGlassStyle == .tinted {
                    HStack {
                        Text("Tint strength")
                        Slider(value: $settings.hudTintStrength, in: 0.05...0.9)
                        Text(settings.hudTintStrength, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: DS.Space.panel + DS.Space.base, alignment: .trailing)
                    }
                }
                if settings.hudGlassStyle != .native {
                    Toggle("Ocean-blue outline", isOn: $settings.hudOutline)
                    Button("Reset to Goul navy") {
                        settings.hudTintColor = GoulTheme.HUD.defaultTint
                        settings.hudTintStrength = GoulTheme.HUD.defaultTintStrength
                        settings.hudOutline = true
                    }.buttonStyle(GoulButtonStyle())
                }
                note("Solid: an opaque pill in your colour, the classic Goul look. Tinted: your colour over Liquid Glass; low strength is nearly transparent. Native: pure macOS glass that takes the colour of what's behind it. Changes apply to the next dictation.")
            }
            group("Crew") {
                Toggle("Brook sits on the pill", isOn: $settings.hudMascotEnabled)
                note("Off gives a plain pill, like other dictation tools.")
            }
            group("Live text") {
                Toggle("Show the sentence in the pill as you speak", isOn: $settings.liveTextEnabled)
                note("The pill widens to show the end of the sentence. Apple Speech streams it; Parakeet shows it on release. Off by default: a small pill with a level meter.")
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            group("History") {
                Toggle("Keep transcript history on this Mac", isOn: $settings.historyEnabled)
                note("Off by default. When off, the log lasts for this session only. Turning it off also removes saved history.")
                Button("Clear the captain’s log") { RunLog.clear() }.buttonStyle(GoulButtonStyle())
            }
            group("Dictionary") {
                Button("Reveal dictionary file") { NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL]) }
                    .buttonStyle(GoulButtonStyle())
                note("Your words and corrections live in one JSON file you can back up or edit.")
            }
            group("Sounds") {
                Toggle("Play recording sounds", isOn: $settings.soundEnabled)
            }
            group("What never leaves this Mac") {
                Label("Audio is processed on-device and never written to disk.", systemImage: "waveform.slash")
                Label("Speech models, language detection and Apple Intelligence run locally.", systemImage: "cpu")
                Label("No account, no analytics, no network after the one-time model downloads.", systemImage: "network.slash")
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            group("Accessibility") {
                status(Permissions.hasAccessibility, on: "Granted", off: "Not granted")
                note("Lets Goul see the shortcut key in other apps and paste into their text fields. Rebuilding the app with a different signature can reset this grant.")
                HStack(spacing: DS.Space.base) {
                    Button("Open Accessibility settings") { Permissions.openAccessibilitySettings() }
                    Button("Request again") { Permissions.promptForAccessibility() }
                }.buttonStyle(GoulButtonStyle())
            }
            group("Microphone") {
                status(Permissions.hasMicrophone, on: "Granted", off: "Not granted")
                note("Requested the first time you dictate or press Prepare.")
                Button("Open Microphone settings") { Permissions.openMicrophoneSettings() }.buttonStyle(GoulButtonStyle())
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            HStack(spacing: DS.Space.base) {
                GoulArtwork(name: "GoulIcon").frame(width: GoulTheme.icon, height: GoulTheme.icon)
                    .clipShape(.rect(cornerRadius: GoulTheme.radius))
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Goul").font(GoulTheme.brand)
                    Text("Version \(Self.version) · Personal edition").font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                }
            }
            group("On board") {
                Label("Apple SpeechAnalyzer and NVIDIA Parakeet v3 (FluidAudio) for speech", systemImage: "waveform")
                Label("Apple Intelligence for cleanup and Command mode", systemImage: "sparkles")
                Label("Apple NaturalLanguage for English/French detection", systemImage: "globe")
                Label("Brook, the Soul King, on the pill", systemImage: "music.mic")
            }
            note("Your voice. Your adventure. Everything stays on this Mac.")
        }
    }

    // MARK: - Pieces

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: DS.Space.base, content: content)
                .padding(DS.Space.base).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func status(_ granted: Bool, on: String, off: String) -> some View {
        HStack(spacing: DS.Space.snug) {
            Circle().fill(granted ? GoulTheme.statusGood : GoulTheme.red)
                .frame(width: GoulTheme.statusDot, height: GoulTheme.statusDot)
            Text(granted ? on : off).fontWeight(.semibold)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One theme in the picker: its scene (or its panel colour) and its name.
private struct ThemeCard: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void
    private typealias S = GoulTheme.Scene
    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                ZStack {
                    if let art = theme.image("background") {
                        art.resizable().scaledToFill()
                    } else {
                        theme.palette.panel
                        HStack(spacing: 0) {
                            theme.palette.chrome.frame(width: S.thumbnailWidth * 0.28)
                            Spacer()
                        }
                    }
                }
                .frame(width: S.thumbnailWidth, height: S.thumbnailHeight)
                .clipShape(.rect(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(selected ? GoulTheme.gold : GoulTheme.line.opacity(0.6), lineWidth: selected ? 2.5 : 1))
                HStack(spacing: DS.Space.tight) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(GoulTheme.gold) }
                    Text(theme.name).font(GoulTheme.caption).foregroundStyle(GoulTheme.ink)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name)\(selected ? ", selected" : "")")
    }
}
