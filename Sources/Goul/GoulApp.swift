import AppKit
import AVFoundation
import SwiftUI

@main
struct GoulApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Goul", id: "main") {
            MainWindow(controller: delegate.controller)
                .onExitCommand { delegate.controller.cancelDictation() }
                // The scene runs under the traffic lights; the title bar is transparent.
                .ignoresSafeArea(.container, edges: .top)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: GoulTheme.Scene.defaultWindow.width, height: GoulTheme.Scene.defaultWindow.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") { NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL]) }
            }
        }
        SwiftUI.Settings { SettingsWindow(controller: delegate.controller).frame(width: GoulTheme.settingsWidth, height: GoulTheme.settingsHeight) }
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state == .listening ? "mic.fill" : "sailboat")
        }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["GOUL_HUD_SNAPSHOT"] {
            Self.snapshotHUD(to: path)
            NSApp.terminate(nil)
            return
        }
        if let slug = ProcessInfo.processInfo.environment["GOUL_THEME_SNAPSHOT"] {
            ThemeManager.shared.select(slug)
            for (label, size) in [("large", CGSize(width: 1280, height: 840)), ("small", CGSize(width: 1000, height: 700))] {
                let renderer = ImageRenderer(content: MainWindow(controller: controller).frame(width: size.width, height: size.height))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "/tmp/goul-theme-\(slug)-\(label).png"))
                }
            }
            NSApp.terminate(nil)
            return
        }
        if let path = ProcessInfo.processInfo.environment["GOUL_SETTINGS_SNAPSHOT"] {
            for section in SettingsWindow.SettingsSection.allCases {
                let renderer = ImageRenderer(content: SettingsWindow(controller: controller, section: section, scrolls: false)
                    .frame(width: GoulTheme.settingsWidth, height: GoulTheme.settingsHeight))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path).deletingPathExtension()
                        .appendingPathExtension("\(section.rawValue.lowercased().filter(\.isLetter)).png"))
                }
            }
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        hud = HUDPanel(controller: controller)
        controller.activate()
        observeState()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controller.interrupted() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controller.interrupted() }
        })
        // Permission grants become visible without restarting the application.
        Task { @MainActor [weak self] in
            while let self, !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(2))
                if Permissions.hasAccessibility { self.controller.activate(); break }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { controller.deactivate() }

    /// Renders the HUD in a few fixed states to PNGs, for checking the layout without a
    /// microphone. Development aid only; triggered by an environment variable.
    private static func snapshotHUD(to path: String) {
        let models: [(String, HUDModel)] = [
            ("listening", HUDModel(state: .listening, level: 0.6)),
            ("working", HUDModel(state: .finishing)),
            ("reviewing", HUDModel(state: .reviewing, transcript: "Can you book the meeting room for Thursday?")),
            ("livetext", HUDModel(state: .listening, transcript: "Est-ce que tu peux réserver la salle pour jeudi", level: 0.4, language: .french, liveText: true)),
        ]
        for (name, model) in models {
            let renderer = ImageRenderer(content: HUDContent(model: model))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("\(name).png")
            try? png.write(to: url)
        }
    }
    private func observeState() {
        withObservationTracking { _ = controller.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive { self.hud?.present() } else { self.hud?.dismiss() }
                self.observeState()
            }
        }
    }
}
private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Goul · EN / FR")
        Text("Hold \(settings.pushToTalkKey.displayName) to dictate")
        Button("Open Goul") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        if controller.state.isActive { Button("Cancel dictation") { controller.cancelDictation() } }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Prepare microphone & model") { controller.prepare() }
        Divider()
        Button("Quit Goul") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
