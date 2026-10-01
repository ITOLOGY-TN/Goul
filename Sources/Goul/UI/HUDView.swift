import AppKit
import GoulCore
import SwiftUI

/// Everything the HUD needs to draw, as plain values.
///
/// Split from the controller so the exact same view can be rendered off-screen (see
/// `GoulApp`'s snapshot hook) and so the layout is checkable without holding a key.
struct HUDModel: Equatable {
    var state: DictationController.State = .listening
    var mode: DictationController.Mode = .dictation
    var transcript = ""
    var level: Float = 0
    var language: SpokenLanguage?
    var liveText = false
    var glass: HUDGlassStyle = .solid
    var tint: Color = GoulTheme.HUD.defaultTint
    var tintStrength: Double = GoulTheme.HUD.defaultTintStrength
    var outline = true
    var mascot = true
    var instrument: Color = GoulTheme.HUD.gold

    @MainActor init(controller: DictationController) {
        state = controller.state
        mode = controller.mode
        transcript = controller.transcript
        level = controller.level
        language = controller.detectedLanguage
        liveText = Settings.shared.liveTextEnabled
        let settings = Settings.shared
        glass = settings.hudGlassStyle
        tint = settings.hudTintColor
        tintStrength = settings.hudTintStrength
        outline = settings.hudOutline
        mascot = settings.hudMascotEnabled
        instrument = GoulTheme.instrument
    }
    init(state: DictationController.State = .listening, mode: DictationController.Mode = .dictation,
         transcript: String = "", level: Float = 0, language: SpokenLanguage? = nil, liveText: Bool = false) {
        self.state = state; self.mode = mode; self.transcript = transcript
        self.level = level; self.language = language; self.liveText = liveText
    }

    var isError: Bool { if case .error = state { return true }; return false }
    var isListening: Bool { state == .starting || state == .listening }
    var isWorking: Bool { state == .finishing }

    /// Text shown inside the pill, if any. Errors always show; the transcript only when
    /// live text is on. Everything else is conveyed by the instrument, not words.
    var text: String? {
        if case .error(let message) = state { return message }
        guard liveText, !transcript.isEmpty else { return nil }
        return transcript
    }
}

/// Live binding: the panel hosts this, and it re-renders as the controller changes.
struct HUDView: View {
    @Bindable var controller: DictationController
    var body: some View {
        // HUDModel reads Settings inside this body, so Observation re-renders on any change.
        HUDContent(model: HUDModel(controller: controller))
    }
}

/// The pill, its instrument, and the miniature Brook.
///
/// Fixed canvas the size of the panel window; the pill is centred at the bottom and
/// grows from the centre when it has text. Nothing is hit-testable — the panel ignores
/// mouse events and never becomes key, so the user's text field keeps focus.
struct HUDContent: View {
    let model: HUDModel
    private typealias T = GoulTheme.HUD

    private var pillWidth: CGFloat {
        if model.text != nil { return T.pillWideWidth }
        return model.isListening ? T.pillWidth : T.pillWorkingWidth
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pill
                .frame(width: pillWidth, height: T.pillHeight)
                .overlay { content }
                // In front of the pill: his legs dangle over it, hips on the top edge.
                .overlay(alignment: .topTrailing) {
                    if model.mascot { BrookMascot()
                        .frame(width: T.mascotHeight * T.mascotAspect, height: T.mascotHeight)
                        .offset(x: T.mascotOverhang, y: -T.mascotHeight * T.mascotSeat)
                        .allowsHitTesting(false) }
                }
                .padding(.bottom, T.margin)
                .animation(T.resize, value: pillWidth)
        }
        .frame(width: T.windowWidth, height: T.windowHeight)
    }

    /// Liquid Glass, tinted navy, with the ocean hairline on top. The panel window is
    /// transparent and non-activating, so the material picks up whatever is behind it.
    @ViewBuilder private var pill: some View {
        switch model.glass {
        case .solid:
            Capsule().fill(model.tint)
                .overlay { if model.outline { Capsule().strokeBorder(T.pillEdge, lineWidth: T.pillEdgeWidth) } }
                .shadow(color: .black.opacity(T.shadowOpacity), radius: T.shadowRadius, y: T.shadowOffset)
        case .native:
            Color.clear.glassEffect(.regular, in: Capsule())
        case .tinted:
            Capsule().fill(model.tint.opacity(model.tintStrength * T.pillBaseFraction))
                .glassEffect(.regular.tint(model.tint.opacity(model.tintStrength)), in: Capsule())
                .overlay { if model.outline { Capsule().strokeBorder(T.pillEdge, lineWidth: T.pillEdgeWidth) } }
                .shadow(color: .black.opacity(T.shadowOpacity), radius: T.shadowRadius, y: T.shadowOffset)
        }
    }

    @ViewBuilder private var content: some View {
        HStack(spacing: T.contentGap) {
            // Brook owns the right end, so everything transient sits on the left.
            if model.state == .reviewing {
                tag("esc").transition(.opacity.combined(with: .scale))
            } else if model.isWorking {
                Spinner().transition(.opacity.combined(with: .scale))
            }
            instrument.foregroundStyle(model.instrument)
            if let text = model.text {
                Text(text)
                    .font(T.font)
                    .foregroundStyle(model.isError ? GoulTheme.red : T.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let language = model.language { tag(language.code) }
            }
        }
        .padding(.leading, T.contentInset)
        .padding(.trailing, model.mascot ? T.mascotClearance : T.contentInset)
        .animation(T.resize, value: model.state)
    }

    /// Speaking: the gold waveform riding the mic level. Otherwise: quiet dots.
    @ViewBuilder private var instrument: some View {
        if model.isListening { LevelBars(level: model.level) } else { IdleDots() }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(T.tagFont)
            .foregroundStyle(T.text.opacity(0.8))
            .padding(.horizontal, DS.Space.tight).padding(.vertical, DS.Space.hair)
            .overlay(Capsule().strokeBorder(T.text.opacity(0.35)))
    }
}

/// The waveform while you speak: bars mirrored about the centre line whose envelope
/// follows the microphone. Each bar has its own phase so the shape rolls instead of
/// pumping; the bell-shaped envelope keeps the ends short like a real trace.
private struct LevelBars: View {
    let level: Float
    private typealias T = GoulTheme.HUD
    private static let phases: [Double] = (0..<T.barCount).map { (Double($0) * 0.618).truncatingRemainder(dividingBy: 1) * .pi * 2 }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: T.barGap) {
                ForEach(0..<T.barCount, id: \.self) { index in
                    Capsule().fill(.foreground)
                        .frame(width: T.barWidth, height: height(index, t))
                }
            }
            .frame(height: T.barMaxHeight)
        }
    }
    private func height(_ index: Int, _ t: TimeInterval) -> CGFloat {
        let centre = 1 - abs(Double(index) - Double(T.barCount - 1) / 2) / (Double(T.barCount) / 2)
        let wave = (sin(t * T.barSpeed + Self.phases[index]) + 1) / 2
        let drive = max(T.barIdleAmplitude, Double(level))
        let amplitude = drive * (0.35 + 0.65 * wave) * (0.35 + 0.65 * centre)
        return T.barMinHeight + CGFloat(amplitude) * (T.barMaxHeight - T.barMinHeight)
    }
}

private struct IdleDots: View {
    private typealias T = GoulTheme.HUD
    var body: some View {
        HStack(spacing: T.dotGap) {
            ForEach(0..<T.dotCount, id: \.self) { _ in
                Circle().fill(.foreground).opacity(0.7).frame(width: T.dotSize, height: T.dotSize)
            }
        }
    }
}

private struct Spinner: View {
    private typealias T = GoulTheme.HUD
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(T.text.opacity(0.9), style: StrokeStyle(lineWidth: T.spinnerWidth, lineCap: .round))
                .frame(width: T.spinnerSize, height: T.spinnerSize)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: T.spinnerSpeed) / T.spinnerSpeed * 360))
        }
    }
}

/// Brook, from the bundle, pre-scaled once to the exact pixel size he is drawn at.
///
/// Drawing the 1500 px render straight into a few dozen points aliased badly on the
/// first pass of this HUD; resampling with high-quality interpolation at load time is
/// what makes the small mascot look drawn rather than shrunk.
private struct BrookMascot: View {
    private typealias T = GoulTheme.HUD
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrookSeated", withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Log.app.error("BrookSeated.png missing from the bundle")
            return nil
        }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let size = CGSize(width: T.mascotHeight * T.mascotAspect * scale, height: T.mascotHeight * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(origin: .zero, size: size))
        guard let scaled = context.makeImage() else { return source }
        return NSImage(cgImage: scaled, size: CGSize(width: T.mascotHeight * T.mascotAspect, height: T.mascotHeight))
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .accessibilityHidden(true)
        }
    }
}
