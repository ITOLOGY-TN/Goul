import AppKit
import Foundation
import Observation
import SwiftUI

/// A theme: a palette, a display font family, and optionally a folder of generated
/// artwork (`Resources/Themes/<slug>/`, see `docs/THEME-ASSET-PROMPT.md`).
///
/// Two kinds exist. The built-in **logbook** theme is colours only and draws the classic
/// parchment-and-ocean layout. An **illustrated** theme carries the full asset pack and
/// switches `MainWindow` to the scene layout: background, sidebar art, 9-slice panel,
/// mascot. Both share every control, so a theme never changes what the app does.
struct Theme: Identifiable, Equatable {
    struct Palette: Equatable {
        var chrome: Color, panel: Color, ink: Color, inkMuted: Color
        var inkOnChrome: Color, accent: Color, record: Color, instrument: Color
    }
    enum FontStyle: String { case serif, sans, mono, rounded }

    let id: String
    let name: String
    let palette: Palette
    let fontStyle: FontStyle
    /// Border thickness of `panel-frame.png`, in source pixels.
    let panelInsets: CGFloat
    let watermarkOpacity: Double
    /// Folder holding the asset pack; nil for colour-only themes.
    let folder: URL?

    var isIllustrated: Bool { folder != nil }

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    /// The classic look, always available, needs no files.
    static let logbook = Theme(
        id: "logbook", name: "Captain's logbook",
        palette: Palette(
            chrome: Color(red: 0.055, green: 0.145, blue: 0.20),
            panel: Color(red: 0.96, green: 0.92, blue: 0.84),
            ink: Color(red: 0.09, green: 0.18, blue: 0.22),
            inkMuted: Color(red: 0.38, green: 0.34, blue: 0.27),
            inkOnChrome: Color(red: 0.96, green: 0.92, blue: 0.84),
            accent: Color(red: 0.86, green: 0.65, blue: 0.31),
            record: Color(red: 0.70, green: 0.19, blue: 0.14),
            instrument: Color(red: 0.96, green: 0.66, blue: 0.18)),
        fontStyle: .serif, panelInsets: 0, watermarkOpacity: 0, folder: nil)

    // MARK: - Loading

    /// The 14-file contract. A folder missing any of these is not a theme.
    static let requiredAssets = [
        "background", "panel-frame", "sidebar", "mascot", "logo-dark", "logo-light",
        "record-idle", "record-active", "ornament-divider", "watermark-1", "watermark-2", "watermark-3",
    ]

    /// Parses `<folder>/theme.json` and checks every asset exists. Logs and returns nil
    /// on any problem, so a half-copied pack can't take the app down.
    static func load(folder: URL) -> Theme? {
        let slug = folder.lastPathComponent
        struct Manifest: Decodable {
            struct Font: Decodable { let display: String }
            let name: String
            let colors: [String: String]
            let font: Font
            let panelInsets: CGFloat
            let watermarkOpacity: Double
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("theme.json")))
        } catch {
            Log.app.error("theme \(slug, privacy: .public): theme.json invalid — \(error.localizedDescription)")
            return nil
        }
        let missing = requiredAssets.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0).png").path) }
        guard missing.isEmpty else {
            Log.app.error("theme \(slug, privacy: .public): missing \(missing.joined(separator: ", "), privacy: .public)")
            return nil
        }
        func color(_ key: String) -> Color? { manifest.colors[key].flatMap(Color.init(hex:)) }
        guard let chrome = color("chrome"), let panel = color("panel"), let ink = color("ink"),
              let inkMuted = color("inkMuted"), let inkOnChrome = color("inkOnChrome"),
              let accent = color("accent"), let record = color("record"), let instrument = color("instrument") else {
            Log.app.error("theme \(slug, privacy: .public): colors must be eight #RRGGBB values")
            return nil
        }
        return Theme(
            id: slug, name: manifest.name,
            palette: Palette(chrome: chrome, panel: panel, ink: ink, inkMuted: inkMuted, inkOnChrome: inkOnChrome,
                             accent: accent, record: record, instrument: instrument),
            fontStyle: FontStyle(rawValue: manifest.font.display) ?? .serif,
            panelInsets: manifest.panelInsets, watermarkOpacity: manifest.watermarkOpacity, folder: folder)
    }

    // MARK: - Assets

    /// An asset by contract name, loaded once per process.
    @MainActor func image(_ name: String) -> Image? {
        ThemeImages.nsImage(self, name).map { Image(nsImage: $0) }
    }

    /// `panel-frame.png` prepared for 9-slice drawing: its point size is set so the border
    /// renders at `GoulTheme.Scene.frameBorder` points whatever the source resolution.
    @MainActor func frameImage() -> Image? {
        ThemeImages.nsImage(self, "panel-frame", pointSize: { source in
            let scale = GoulTheme.Scene.frameBorder / max(panelInsets, 1)
            return CGSize(width: source.width * scale, height: source.height * scale)
        }).map { Image(nsImage: $0) }
    }
    @MainActor var frameCapInsets: EdgeInsets {
        let b = GoulTheme.Scene.frameBorder
        return EdgeInsets(top: b, leading: b, bottom: b, trailing: b)
    }
}

extension Color {
    /// `#RRGGBB` → Color, nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Per-process cache of theme bitmaps. Backgrounds are 10 MB PNGs; decode them once.
@MainActor
enum ThemeImages {
    private static var cache: [String: NSImage] = [:]

    static func nsImage(_ theme: Theme, _ name: String, pointSize: ((CGSize) -> CGSize)? = nil) -> NSImage? {
        guard let folder = theme.folder else { return nil }
        let key = theme.id + "/" + name
        if let hit = cache[key] { return hit }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent("\(name).png")) else {
            Log.app.error("theme \(theme.id, privacy: .public): could not decode \(name, privacy: .public).png")
            return nil
        }
        if let pointSize, let rep = image.representations.first {
            image.size = pointSize(CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        }
        cache[key] = image
        return image
    }
}

/// Knows every theme on disk and which one is active. Views read `current`; Observation
/// re-renders them when it changes.
@MainActor @Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var themes: [Theme] = [.logbook]
    private(set) var current: Theme = .logbook

    private init() {
        reload()
        select(UserDefaults.standard.string(forKey: "themeID") ?? Theme.logbook.id)
    }

    /// Scans `Contents/Resources/Themes/*/`. Safe to call again after dropping in a pack.
    func reload() {
        var found: [Theme] = [.logbook]
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Themes"),
           let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if let theme = Theme.load(folder: folder) { found.append(theme) }
            }
        }
        themes = found
        Log.app.info("themes: \(found.map(\.id).joined(separator: ", "), privacy: .public)")
    }

    func select(_ id: String) {
        current = themes.first { $0.id == id } ?? .logbook
        UserDefaults.standard.set(current.id, forKey: "themeID")
    }
}
