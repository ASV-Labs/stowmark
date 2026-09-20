@preconcurrency import AppKit
import SwiftUI

/// Menu-bar quick capture: save the clipboard or focus the main window without hunting for it.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "menuBarCaptureEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "menuBarCaptureEnabled") }
    }

    func install() {
        guard isEnabled else {
            tearDown()
            return
        }
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Cardfile")
            button.toolTip = "Cardfile — save from clipboard"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Save from Clipboard", action: #selector(saveClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Open Cardfile", action: #selector(openApp), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        let hide = menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
        hide.target = self
        for entry in menu.items where entry.action != #selector(hideIcon) {
            entry.target = self
        }
        item.menu = menu
        statusItem = item
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            install()
        } else {
            tearDown()
        }
    }

    private func tearDown() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func saveClipboard() {
        AppModel.shared.captureFromClipboard()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.isEmpty {
            NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
        }
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        openApp()
        NotificationCenter.default.post(name: .openCardfileSettings, object: nil)
    }

    @objc private func hideIcon() {
        setEnabled(false)
    }
}
