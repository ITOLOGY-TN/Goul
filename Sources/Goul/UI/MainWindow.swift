import MurmurDictionary
import GoulCore
import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var section: Section = .dictation
    @State private var settings = Settings.shared
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var showClear = false
    enum Section: String, CaseIterable {
        case dictation = "Dictation", dictionary = "Dictionary", settings = "Settings"
        var symbol: String {
            switch self { case .dictation: "waveform"; case .dictionary: "book.closed"; case .settings: "slider.horizontal.3" }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                if section == .dictation {
                    masthead
                    dictation
                } else if section == .dictionary {
                    pageHeader("Your word treasure", detail: "Teach Goul names, places, and the words that matter to you.")
                    DictionaryPanel().padding(GoulTheme.inset)
                } else {
                    pageHeader("Ship settings", detail: "Your shortcut, local engine, and privacy preferences.")
                    SettingsWindow(controller: controller).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoulTheme.paper)
        }
        .frame(minWidth: GoulTheme.minimumWidth, minHeight: GoulTheme.minimumHeight)
        .preferredColorScheme(.light)
        .tint(GoulTheme.ocean)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: GoulTheme.gap) {
            HStack(spacing: DS.Space.base) {
                GoulArtwork(name: "GoulIcon").frame(width: GoulTheme.icon, height: GoulTheme.icon)
                    .clipShape(.rect(cornerRadius: GoulTheme.radius)).accessibilityHidden(true)
                Text("Goul").font(GoulTheme.brand).foregroundStyle(GoulTheme.paper)
            }.padding(.bottom, DS.Space.wide)
            ForEach(Section.allCases, id: \.self) { item in
                Button { section = item } label: {
                    HStack(spacing: DS.Space.base) {
                        Image(systemName: item.symbol).frame(width: DS.Space.roomy)
                        Text(item.rawValue).font(GoulTheme.body)
                        Spacer()
                    }
                    .foregroundStyle(section == item ? GoulTheme.ocean : GoulTheme.paper)
                    .padding(DS.Space.base)
                    .background(section == item ? GoulTheme.gold : .clear,
                                in: .rect(cornerRadius: DS.Radius.control))
                }.buttonStyle(.plain)
            }
            Spacer()
            Image(systemName: "sailboat").font(.system(size: 32, weight: .light))
                .foregroundStyle(GoulTheme.gold).accessibilityHidden(true)
            Text("Your voice.\nYour adventure.")
                .font(.custom("Baskerville", size: 22)).foregroundStyle(GoulTheme.paper)
                .lineSpacing(DS.Space.tight)
            Divider().overlay(GoulTheme.gold.opacity(0.4)).padding(.vertical, DS.Space.snug)
            Label("On-device dictation", systemImage: "lock.shield")
                .font(GoulTheme.caption).foregroundStyle(GoulTheme.paper.opacity(0.85))
            Text("English · Français · Personal edition")
                .font(GoulTheme.caption).foregroundStyle(GoulTheme.paper.opacity(0.7))
        }
        .padding(DS.Space.wide)
        .frame(width: GoulTheme.rail, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(GoulTheme.ocean)
    }
    private var masthead: some View {
        ZStack(alignment: .leading) {
            GoulTheme.ocean
            GoulArtwork(name: "Voyage").frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [GoulTheme.ocean, GoulTheme.ocean.opacity(0.76), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text("Speak freely,\ncaptain.").font(GoulTheme.heading).foregroundStyle(GoulTheme.paper)
                Text("Hold \(settings.pushToTalkKey.displayName). Speak. Release.")
                    .font(GoulTheme.body).foregroundStyle(GoulTheme.paper.opacity(0.9))
            }.padding(GoulTheme.inset)
        }
        .frame(height: GoulTheme.heroHeight)
        .clipped()
    }
    private func pageHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text(title).font(GoulTheme.heading)
            Text(detail).font(GoulTheme.body).foregroundStyle(GoulTheme.muted)
        }.foregroundStyle(GoulTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
            .padding(GoulTheme.inset)
    }
    private var dictation: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            recorder
            if !controller.setupMessage.isEmpty {
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Image(systemName: "info.circle")
                    Text(controller.setupMessage).textSelection(.enabled)
                }.font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
            }
            Divider().overlay(GoulTheme.line)
            HStack {
                Text("Captain’s log").font(GoulTheme.title).foregroundStyle(GoulTheme.ink)
                Spacer()
                Text(settings.historyEnabled ? "Saved on this Mac" : "This session only")
                    .font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                if !store.runs.isEmpty {
                    Button("Clear") { showClear = true }.buttonStyle(.plain)
                        .foregroundStyle(GoulTheme.muted)
                }
            }
            if store.runs.isEmpty {
                VStack(spacing: DS.Space.base) {
                    Image(systemName: "text.bubble").font(.system(size: 30, weight: .light)).foregroundStyle(GoulTheme.muted)
                    Text("Every adventure begins with a word.").font(GoulTheme.title).foregroundStyle(GoulTheme.ink)
                    Text("Try the microphone here first. Your transcript will appear below.\nTo type into another app, focus its text field and hold your shortcut.")
                        .font(GoulTheme.body).foregroundStyle(GoulTheme.muted)
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search your log", text: $query).textFieldStyle(.plain)
                }.font(GoulTheme.body).foregroundStyle(GoulTheme.muted)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.roomy) {
                        ForEach(store.runs.reversed().filter { query.isEmpty || $0.text.localizedStandardContains(query) }) { run in
                            LogEntry(run: run)
                        }
                    }
                }
            }
        }.padding(GoulTheme.inset)
            .confirmationDialog("Clear the captain’s log?", isPresented: $showClear) {
                Button("Clear all transcripts", role: .destructive) { RunLog.clear() }
            }
    }
    private var recorder: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            HStack(spacing: DS.Space.roomy) {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    HStack(spacing: DS.Space.snug) {
                        Circle().fill(controller.state == .listening ? GoulTheme.red : GoulTheme.muted)
                            .frame(width: DS.Space.snug, height: DS.Space.snug)
                        Text(controller.statusTitle).font(.system(size: 17, weight: .semibold))
                    }
                    HStack(spacing: DS.Space.snug) {
                        Text("\(settings.engine.displayName) · English / Français, detected automatically")
                        if let language = controller.detectedLanguage {
                            LanguageBadge(language: language)
                        }
                    }.font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
                }
                Spacer()
                if controller.state.isActive {
                    Button("Cancel") { controller.cancelDictation() }.buttonStyle(GoulButtonStyle())
                    if controller.state == .listening {
                        Button { controller.stopButtonRecording() } label: { Label("Finish", systemImage: "stop.fill") }
                            .buttonStyle(GoulButtonStyle(primary: true))
                    }
                } else {
                    Button { controller.prepare() } label: { Label("Prepare", systemImage: "checkmark.shield") }
                        .buttonStyle(GoulButtonStyle()).disabled(controller.isPreparing)
                    Button { controller.startButtonRecording() } label: { Label("Test microphone", systemImage: "mic.fill") }
                        .buttonStyle(GoulButtonStyle(primary: true)).disabled(controller.isPreparing)
                }
            }.foregroundStyle(GoulTheme.ink)
            if controller.state.isActive {
                ProgressView(value: Double(controller.level)).tint(GoulTheme.red)
                if !controller.transcript.isEmpty {
                    Text(controller.transcript).font(GoulTheme.body).foregroundStyle(GoulTheme.ink)
                        .lineLimit(3).textSelection(.enabled)
                }
            }
            if case .error(let message) = controller.state {
                Text(message).font(GoulTheme.caption).foregroundStyle(GoulTheme.red).textSelection(.enabled)
            }
        }
    }
}

private struct LogEntry: View {
    let run: DictationRun
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack {
                Text(run.date, style: .time)
                Text("· \(run.engine)")
                if let code = run.language, let language = SpokenLanguage.allCases.first(where: { $0.code == code }) {
                    LanguageBadge(language: language)
                }
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }.buttonStyle(.plain).fontWeight(.semibold)
                Button { RunLog.delete(run) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Delete transcript").accessibilityLabel("Delete transcript")
            }.font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
            Text(run.text).font(GoulTheme.body).foregroundStyle(GoulTheme.ink).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let corrections = run.corrections, !corrections.isEmpty {
                Text("\(corrections.count) dictionary correction(s)").font(GoulTheme.caption).foregroundStyle(GoulTheme.muted)
            }
            Divider().overlay(GoulTheme.line.opacity(0.5))
        }
    }
}

/// Two-letter language tag. Informational: it reports what was heard, it isn't a control.
struct LanguageBadge: View {
    let language: SpokenLanguage
    var body: some View {
        Text(language.code)
            .font(GoulTheme.caption).foregroundStyle(GoulTheme.ocean)
            .padding(.horizontal, DS.Space.snug).padding(.vertical, DS.Space.tight)
            .background(GoulTheme.gold.opacity(0.35), in: .capsule)
            .accessibilityLabel("Detected language: \(language.displayName)")
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        }.font(GoulTheme.body).foregroundStyle(DS.Color.inkOnDeck)
            .padding(DS.Space.base).background(DS.Color.deck)
    }
}
struct EmptyPanel: View {
    let label: String
    let detail: String
    var body: some View {
        VStack(spacing: DS.Space.base) {
            Text(label).font(GoulTheme.title)
            Text(detail).font(GoulTheme.body)
        }.foregroundStyle(DS.Color.inkOnDeck).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
