import AppKit
import SwiftUI

// THESIS: A Straw Hat captain's logbook for private dictation.
// OWN-WORLD: Ocean-blue navigation, parchment workspace, brass rules, manga artwork.
// STORY: Prepare the microphone, test English, then dictate into another app.
// FIRST VIEWPORT: Crew rail at left; illustrated masthead, recorder and log at right.
// FORM: User-pinned One Piece world; seed daeb83d0 yields to the explicit brief.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md.
enum GoulTheme {
    // Palette and display fonts follow the active theme. Main-actor because the manager
    // is; every SwiftUI body runs there. Layout tokens below stay plain constants.
    @MainActor private static var palette: Theme.Palette { ThemeManager.shared.current.palette }
    @MainActor static var ocean: Color { palette.chrome }
    @MainActor static var paper: Color { palette.panel }
    @MainActor static var ink: Color { palette.ink }
    @MainActor static var muted: Color { palette.inkMuted }
    @MainActor static var gold: Color { palette.accent }
    @MainActor static var line: Color { palette.inkMuted.opacity(0.5) }
    @MainActor static var red: Color { palette.record }
    @MainActor static var inkOnChrome: Color { palette.inkOnChrome }
    @MainActor static var instrument: Color { palette.instrument }

    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12, weight: .medium)
    @MainActor static var heading: Font { display(34) }
    @MainActor static var title: Font { display(23) }
    @MainActor static var brand: Font { display(36) }
    @MainActor static func display(_ size: CGFloat) -> Font {
        switch ThemeManager.shared.current.fontStyle {
        case .serif: .custom("Baskerville-Bold", size: size)
        case .sans: .system(size: size, weight: .bold)
        case .mono: .system(size: size, weight: .bold, design: .monospaced)
        case .rounded: .system(size: size, weight: .bold, design: .rounded)
        }
    }
    static let rail: CGFloat = 208
    static let inset: CGFloat = 28
    static let gap: CGFloat = 16
    static let radius: CGFloat = 12
    static let icon: CGFloat = 66
    static let minimumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 650
    static let heroHeight: CGFloat = 172
    static let buttonHeight: CGFloat = 42
    /// The settings page: section list on the left, one section's controls on the right.
    static let settingsRail: CGFloat = 184
    static let settingsWidth: CGFloat = 780
    static let settingsHeight: CGFloat = 640
    static let statusDot: CGFloat = 9
    static let statusGood = Color(red: 0.36, green: 0.62, blue: 0.30)

    /// The illustrated-theme layout (asset packs). Sizes only; colours come from the theme.
    enum Scene {
        /// On-screen thickness of the 9-slice panel frame, whatever the source resolution.
        static let frameBorder: CGFloat = 40
        /// Content padding inside the frame border.
        static let panelPadding: CGFloat = 22
        static let panelMargin: CGFloat = 24
        static let logoHeight: CGFloat = 84
        static let dividerHeight: CGFloat = 12
        static let recordSize: CGFloat = 176
        static let recordGlyph: CGFloat = 60
        static let watermarkSize: CGFloat = 200
        static let mascotColumn: CGFloat = 300
        /// Below this window width the mascot column is dropped.
        static let mascotMinimumWidth: CGFloat = 1180
        static let mascotHeightFraction: CGFloat = 0.78
        static let navPillOpacity: Double = 0.22
        static let cardOpacity: Double = 0.42
        static let cardRadius: CGFloat = 14
        static let logoSidebarHeight: CGFloat = 96
        static let logMaxHeight: CGFloat = 260
        /// Content height at which the dictation page is drawn at full size; below it,
        /// logo, button and spacing scale down proportionally so nothing leaves the panel.
        static let referenceHeight: CGFloat = 780
        static let referenceWidth: CGFloat = 640
        /// Illustrated themes need more room than the classic layout.
        static let minimumWindow = CGSize(width: 1040, height: 760)
        static let contentSpacing: CGFloat = 14
        static let defaultWindow = CGSize(width: 1280, height: 840)
        static let thumbnailWidth: CGFloat = 132
        static let thumbnailHeight: CGFloat = 82
    }

    /// The floating HUD: a small Wispr-Flow-sized pill with a miniature Brook peeking over
    /// its right end. No text by default; `Settings.liveTextEnabled` widens it to show the
    /// tail of the sentence. Every number lives here.
    enum HUD {
        static let pillHeight: CGFloat = 34
        static let pillWidth: CGFloat = 132
        /// Width while working or reviewing: room for the spinner / `esc` on the left.
        /// The change is animated, so the pill visibly "breathes out" when it starts thinking.
        static let pillWorkingWidth: CGFloat = 168
        /// Width when live text is on and there is text to show.
        static let pillWideWidth: CGFloat = 380
        /// Tint colour and strength come from Settings (user-chosen). The solid base under
        /// the glass is this fraction of the tint strength, so the pill still reads over a
        /// light wallpaper (and shows in off-screen snapshots, which have no backdrop).
        static let pillBaseFraction: Double = 0.2
        /// Factory tint: Goul's navy, nearly transparent.
        static let defaultTint = Color(red: 0.06, green: 0.165, blue: 0.235)
        static let defaultTintStrength = 0.65
        static let pillEdge = Color(red: 0.16, green: 0.36, blue: 0.50)
        static let pillEdgeWidth: CGFloat = 1
        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGFloat = 5
        static let shadowOpacity: Double = 0.22
        static let resize = Animation.spring(response: 0.38, dampingFraction: 0.72)

        /// Brook, seated on the pill's right end with his legs in front of it.
        /// Height of the figure; width follows `Resources/BrookSeated.png` (155×240).
        static let mascotHeight: CGFloat = 64
        static let mascotAspect: CGFloat = 155.0 / 240.0
        /// Fraction of his height above the pill's top edge (his hips sit on it).
        static let mascotSeat: CGFloat = 0.57
        /// Fraction of his width hanging past the pill's right edge.
        static let mascotOverhangFraction: CGFloat = -0.18
        static var mascotOverhang: CGFloat { mascotHeight * mascotAspect * mascotOverhangFraction }
        /// Content stays clear of his legs on the right.
        static let mascotClearance: CGFloat = 52

        static let margin: CGFloat = 34
        /// Gap between the pill's bottom and the top of the Dock (or screen bottom).
        static let dockGap: CGFloat = 10
        static var windowWidth: CGFloat { pillWideWidth + mascotOverhang + margin * 2 }
        static var windowHeight: CGFloat { pillHeight + mascotHeight * mascotSeat + margin * 2 }

        /// The waveform: dense bars mirrored about the centre line, like the reference.
        static let barCount = 17
        static let barWidth: CGFloat = 2
        static let barGap: CGFloat = 2
        static let barMinHeight: CGFloat = 3
        static let barMaxHeight: CGFloat = 20
        static let barSpeed: Double = 7.0
        /// Silence still breathes a little, so the meter reads as alive, not stuck.
        static let barIdleAmplitude: Double = 0.12
        static let dotCount = 9
        static let dotSize: CGFloat = 3
        static let dotGap: CGFloat = 3.5
        static let gold = Color(red: 0.96, green: 0.66, blue: 0.18)
        static let spinnerSize: CGFloat = 12
        static let spinnerWidth: CGFloat = 1.6
        static let spinnerSpeed: Double = 1.1

        static let text = Color(red: 0.98, green: 0.95, blue: 0.88)
        static let font = Font.system(size: 13, weight: .medium, design: .rounded)
        static let tagFont = Font.system(size: 9, weight: .bold, design: .rounded)
        static let contentInset: CGFloat = 14
        static let contentGap: CGFloat = 10
    }
}
struct GoulArtwork: View {
    let name: String
    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "sailboat.fill").resizable().scaledToFit()
                .foregroundStyle(GoulTheme.gold)
        }
    }
}

struct GoulButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, DS.Space.roomy)
            .frame(height: GoulTheme.buttonHeight)
            .foregroundStyle(primary ? GoulTheme.paper : GoulTheme.ink)
            .background(primary ? GoulTheme.ocean : Color.white.opacity(0.35),
                        in: .rect(cornerRadius: DS.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                .strokeBorder(GoulTheme.line.opacity(primary ? 0 : 0.7)))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
