import AppKit
import GoulCore
import SwiftUI

/// The main window for an illustrated theme: the generated scene as backdrop, the
/// sidebar art with the theme's logo, a 9-slice panel that hosts every section, and the
/// mascot in a column of its own on wide windows. Same controller, same sections, same
/// controls as the classic layout; only the dressing changes.
struct IllustratedScene: View {
    @Bindable var controller: DictationController
    let theme: Theme
    @Binding var section: MainWindow.Section
    @State private var settings = Settings.shared
    @State private var store = RunStore.shared
    private typealias S = GoulTheme.Scene

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Scene under the traffic lights, like the mockup: no title bar strip.
                theme.image("background")?.resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                HStack(spacing: 0) {
                    sidebar.frame(width: GoulTheme.rail)
                    panel.padding(S.panelMargin).padding(.top, DS.Space.base)
                    if geometry.size.width >= S.mascotMinimumWidth {
                        mascot(height: geometry.size.height * S.mascotHeightFraction)
                            .frame(width: S.mascotColumn).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            theme.image("sidebar")?.resizable().scaledToFill().clipped()
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                theme.image("logo-dark")?.resizable().scaledToFit()
                    .frame(height: S.logoSidebarHeight).frame(maxWidth: .infinity)
                    .padding(.horizontal, -DS.Space.base)  // let the lockup use the rail's full width
                    .padding(.top, DS.Space.panel).padding(.bottom, DS.Space.wide).accessibilityLabel("Goul")
                ForEach(MainWindow.Section.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        HStack(spacing: DS.Space.base) {
                            Image(systemName: item.symbol).frame(width: DS.Space.roomy)
                            Text(item.rawValue).font(GoulTheme.body)
                            Spacer()
                        }
                        .foregroundStyle(GoulTheme.inkOnChrome)
                        .padding(DS.Space.base)
                        .background(section == item ? GoulTheme.inkOnChrome.opacity(S.navPillOpacity) : .clear,
                                    in: .rect(cornerRadius: DS.Radius.control))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                            .strokeBorder(section == item ? GoulTheme.gold.opacity(0.8) : .clear))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("On-device dictation", systemImage: "lock.shield")
                    .font(GoulTheme.caption).foregroundStyle(GoulTheme.inkOnChrome.opacity(0.85))
                Text("English · Français")
                    .font(GoulTheme.caption).foregroundStyle(GoulTheme.inkOnChrome.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.wide)
            .frame(width: GoulTheme.rail, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: GoulTheme.rail)
        .clipped()
    }

    // MARK: - Panel

    private var panel: some View {
        ZStack {
            theme.frameImage()?.resizable(capInsets: theme.frameCapInsets, resizingMode: .stretch)
            watermarks.padding(S.contentInset)
            Group {
                switch section {
                case .dictation: dictation
                case .log:
                    VStack(alignment: .leading, spacing: DS.Space.base) {
                        header("Captain’s log", detail: settings.historyEnabled ? "Saved on this Mac." : "This session only. Turn on history in Settings to keep it.")
                        LogPage()
                    }
                case .dictionary:
                    VStack(alignment: .leading, spacing: DS.Space.base) {
                        header("Your word treasure", detail: "Teach Goul names, places, and the words that matter to you.")
                        DictionaryPanel()
                    }
                case .settings:
                    VStack(alignment: .leading, spacing: DS.Space.base) {
                        header("Ship settings", detail: "Your shortcut, local engine, and privacy preferences.")
                        SettingsWindow(controller: controller, transparent: true)
                    }
                }
            }
            .padding(S.contentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var watermarks: some View {
        GeometryReader { g in
            let size = min(S.watermarkSize, g.size.width * 0.28)
            theme.image("watermark-1")?.resizable().scaledToFit().frame(width: size)
                .position(x: g.size.width - size * 0.6, y: size * 0.55)
            theme.image("watermark-2")?.resizable().scaledToFit().frame(width: size)
                .position(x: g.size.width - size * 0.55, y: g.size.height * 0.52)
            theme.image("watermark-3")?.resizable().scaledToFit().frame(width: size)
                .position(x: size * 0.55, y: g.size.height * 0.28)
        }
        .opacity(theme.watermarkOpacity)
        .allowsHitTesting(false)
    }

    private func header(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(title).font(GoulTheme.heading)
            Text(detail).font(GoulTheme.body).foregroundStyle(GoulTheme.muted)
        }.foregroundStyle(GoulTheme.ink)
    }

    private var divider: some View {
        theme.image("ornament-divider")?.resizable().scaledToFit().frame(height: S.dividerHeight).opacity(0.8)
    }

    // MARK: - Dictation page

    private var dictation: some View {
        GeometryReader { g in
            let k = min(1, g.size.height / S.referenceHeight, g.size.width / S.referenceWidth)
            // No ScrollView: everything scales with `k` so the page always fits the panel.
                VStack(spacing: S.contentSpacing * k) {
                    Spacer(minLength: 0)
                    theme.image("logo-light")?.resizable().scaledToFit().frame(height: S.logoHeight * k).accessibilityLabel("Goul")
                    divider
                    recordButton(size: S.recordSize * k)
                    Text(controller.state.isActive || controller.isPreparing
                         ? controller.statusTitle : "Hold \(settings.pushToTalkKey.displayName) to speak")
                        .font(GoulTheme.title).foregroundStyle(GoulTheme.ink)
                    if controller.state.isActive {
                        ProgressView(value: Double(controller.level)).tint(GoulTheme.red).frame(maxWidth: S.recordSize * 2)
                        if !controller.transcript.isEmpty {
                            Text(controller.transcript).font(GoulTheme.body).foregroundStyle(GoulTheme.ink)
                                .lineLimit(2).textSelection(.enabled).multilineTextAlignment(.center)
                        }
                    }
                    if case .error(let message) = controller.state {
                        Text(message).font(GoulTheme.caption).foregroundStyle(GoulTheme.red).textSelection(.enabled)
                    }
                    divider
                    languagePill
                    if !controller.setupMessage.isEmpty {
                        Text(controller.setupMessage).font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                            .multilineTextAlignment(.center).textSelection(.enabled)
                            .lineLimit(k < 1 ? 1 : 3).truncationMode(.tail)
                    }
                    if let last = store.runs.last { lastEntry(last) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func recordButton(size: CGFloat) -> some View {
        let active = controller.state.isActive
        return Button {
            active ? controller.stopButtonRecording() : controller.startButtonRecording()
        } label: {
            ZStack {
                theme.image(active ? "record-active" : "record-idle")?.resizable().scaledToFit()
                Image(systemName: active ? "stop.fill" : "mic.fill")
                    .font(.system(size: S.recordGlyph * size / S.recordSize, weight: .semibold))
                    .foregroundStyle(GoulTheme.inkOnChrome)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .disabled(controller.isPreparing)
        .help(active ? "Finish the test recording" : "Test the microphone here; text stays in the log")
        .accessibilityLabel(active ? "Finish test recording" : "Test microphone")
    }

    private var languagePill: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "globe")
            Text("Auto-detect · English / Français")
            if let language = controller.detectedLanguage { LanguageBadge(language: language) }
        }
        .font(GoulTheme.body).foregroundStyle(GoulTheme.ink)
        .padding(.horizontal, DS.Space.roomy).padding(.vertical, DS.Space.snug)
        .overlay(Capsule().strokeBorder(GoulTheme.ink.opacity(0.35)))
        .accessibilityLabel("Language detected automatically: English or French")
    }

    /// A one-line reminder of the latest transcript; the full log has its own page.
    private func lastEntry(_ run: DictationRun) -> some View {
        Button { section = .log } label: {
            HStack(spacing: DS.Space.base) {
                Image(systemName: "book.closed")
                Text(run.text).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
            .padding(DS.Space.base)
            .background(Color.white.opacity(S.cardOpacity), in: .rect(cornerRadius: S.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: S.cardRadius).strokeBorder(GoulTheme.ink.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the captain’s log")
    }

    // MARK: - Mascot

    private func mascot(height: CGFloat) -> some View {
        theme.image("mascot")?.resizable().scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
            .accessibilityHidden(true)
    }
}
