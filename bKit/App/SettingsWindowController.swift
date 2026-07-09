//
//  SettingsWindowController.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let pluginManager: PluginManager
    private let clearHistory: () -> Void
    private var window: NSWindow?

    init(settings: SettingsStore, pluginManager: PluginManager, clearHistory: @escaping () -> Void) {
        self.settings = settings
        self.pluginManager = pluginManager
        self.clearHistory = clearHistory
    }

    func show() {
        let window = window ?? makeWindow()
        updateWindow(window)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func prewarm() {
        // 提前构造设置窗口，但先不显示。
        // 这样用户第一次点击 Settings 时，就不需要再承担首屏建树成本。
        _ = window ?? makeWindow()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.toolbarStyle = .unified
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 520, height: 520)
        updateWindow(window)

        self.window = window
        return window
    }

    private func updateWindow(_ window: NSWindow) {
        // 设置窗口标题和内容都跟着应用内语言一起刷新。
        let localizer = Localizer(language: settings.language)
        window.title = localizer.settingsTitle
        window.contentView = NSHostingView(
            rootView: GlassContainer {
                SettingsView(settings: settings, pluginManager: pluginManager, clearHistory: clearHistory)
            }
        )
    }
}

private struct GlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            SettingsGlassBackground()
            content
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct SettingsGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.state = .active
        view.blendingMode = .withinWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
