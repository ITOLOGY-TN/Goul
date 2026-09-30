import AppKit
import SwiftUI

// THESIS: A Straw Hat captain's logbook for private dictation.
// OWN-WORLD: Ocean-blue navigation, parchment workspace, brass rules, manga artwork.
// STORY: Prepare the microphone, test English, then dictate into another app.
// FIRST VIEWPORT: Crew rail at left; illustrated masthead, recorder and log at right.
// FORM: User-pinned One Piece world; seed daeb83d0 yields to the explicit brief.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md.
enum GoulTheme {
    static let ocean = Color(red: 0.055, green: 0.145, blue: 0.20)
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.84)
    static let ink = Color(red: 0.09, green: 0.18, blue: 0.22)
    static let muted = Color(red: 0.38, green: 0.34, blue: 0.27)
    static let gold = Color(red: 0.86, green: 0.65, blue: 0.31)
    static let line = Color(red: 0.76, green: 0.68, blue: 0.52)
    static let red = Color(red: 0.70, green: 0.19, blue: 0.14)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12, weight: .medium)
    static let heading = Font.custom("Baskerville-Bold", size: 34)
    static let title = Font.custom("Baskerville-Bold", size: 23)
    static let brand = Font.custom("Baskerville-Bold", size: 36)
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
