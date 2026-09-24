import AppKit
import SwiftUI

@main
struct AvertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)

        Window("Avert", id: "avert.main") {
            MainWindowContainer(model: appDelegate.model)
        }
        .defaultSize(width: 780, height: 520)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Avert") {
                    NotificationCenter.default.post(name: .avertOpenMainWindow, object: nil)
                    NotificationCenter.default.post(name: .avertShowAbout, object: nil)
                }
            }
        }
    }
}

private struct MenuBarLabel: View {
    @Bindable var model: AppModel

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityTitle)
            .help(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        if model.isPanicBlurActive { return "Avert — panic blur on" }
        if model.isEnabled { return "Avert — on" }
        return "Avert — off"
    }
}

private struct MainWindowContainer: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsRootView(model: model)
            .background(WindowAccessor())
            .onReceive(NotificationCenter.default.publisher(for: .avertOpenMainWindow)) { _ in
                openWindow(id: "avert.main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .avertOpenNeckExercises)) { _ in
                openWindow(id: "avert.main")
                NSApp.activate(ignoringOtherApps: true)
                model.openExerciseSession()
            }
    }
}

/// Tags the settings window for reopen / menu Open.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier("avert.main")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = NSUserInterfaceItemIdentifier("avert.main")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shutdown()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .avertOpenMainWindow, object: nil)
        return true
    }
}

private struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.statusLine) {}
            .disabled(true)

        Divider()

        Button("Open Avert…") {
            openWindow(id: "avert.main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        Toggle("Enable Avert", isOn: Binding(
            get: { model.isEnabled },
            set: { model.setEnabled($0) }
        ))
        .keyboardShortcut("e")

        Button("Calibrate…") {
            openWindow(id: "avert.main")
            NSApp.activate(ignoringOtherApps: true)
            model.openCalibrationFlow()
        }
        .keyboardShortcut("c")
        .disabled(!model.isEnabled)

        if model.phase == .motionUnavailable || model.phase == .waitingForMotion {
            Button("Bring AirPods to Mac") {
                model.bringAirPodsToMac()
            }
        }

        Button(model.isPanicBlurActive ? "Clear panic blur" : "Panic blur") {
            model.togglePanicBlur()
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])

        Divider()

        Button("Quit Avert") {
            model.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
