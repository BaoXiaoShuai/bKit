//
//  AppState.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 应用控制能力
import AppKit
// Combine 状态发布能力
import Combine
// SwiftUI 应用状态能力
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let pluginManager = PluginManager()

    let settings: SettingsStore
    let clipboardStore: ClipboardStore
    let codexQuotaStore: CodexQuotaStore

    private let clipboardPlugin: ClipboardPlugin
    private let codexQuotaPlugin: CodexQuotaPlugin
    private let systemMonitorPlugin: SystemMonitorPlugin

    private let hotKeyManager: HotKeyManager
    private let pinWindowHotKeyManager: HotKeyManager
    private let historyPanelController: HistoryPanelController
    private let pasteCoordinator: PasteCoordinator
    private let clipboardMonitor: ClipboardMonitor
    private let settingsWindowController: SettingsWindowController
    private var mainPanelController: MainPanelController?
    private var cancellables: Set<AnyCancellable> = []
    private var isRevertingShortcutRegistrationFailure = false
    private var statusBarController: StatusBarController?

    private init() {
        clipboardPlugin = ClipboardPlugin()
        settings = clipboardPlugin.settings
        clipboardStore = clipboardPlugin.store
        codexQuotaPlugin = CodexQuotaPlugin()
        codexQuotaStore = codexQuotaPlugin.store
        systemMonitorPlugin = SystemMonitorPlugin()

        pluginManager.register(clipboardPlugin)
        pluginManager.register(codexQuotaPlugin)
        pluginManager.register(systemMonitorPlugin)

        let pasteCoordinator = PasteCoordinator(store: clipboardStore)
        self.pasteCoordinator = pasteCoordinator

        let settingsWindowController = SettingsWindowController(
            settings: settings,
            pluginManager: pluginManager,
            clearHistory: { [weak clipboardStore] in
                clipboardStore?.clearAll()
            }
        )
        self.settingsWindowController = settingsWindowController

        let historyPanelController = HistoryPanelController(
            store: clipboardStore,
            settings: settings,
            pasteCoordinator: pasteCoordinator,
            openSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            }
        )
        self.historyPanelController = historyPanelController

        let hotKeyManager = HotKeyManager()
        self.hotKeyManager = hotKeyManager

        let pinWindowHotKeyManager = HotKeyManager(id: 2)
        self.pinWindowHotKeyManager = pinWindowHotKeyManager

        let clipboardMonitor = ClipboardMonitor(store: clipboardStore, settings: settings)
        self.clipboardMonitor = clipboardMonitor

        let statusBarController = StatusBarController(
            codexQuotaPlugin: codexQuotaPlugin,
            codexQuotaStore: codexQuotaStore,
            systemMonitorPlugin: systemMonitorPlugin,
            onLeftClick: { [weak self] in
                self?.toggleMainPanel()
            },
            onOpenSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        self.statusBarController = statusBarController

        let mainPanelController = MainPanelController(
            statusItem: statusBarController.statusItem,
            pluginManager: pluginManager,
            clipboardStore: clipboardStore,
            codexQuotaStore: codexQuotaStore,
            systemMonitorPlugin: systemMonitorPlugin,
            openSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            },
            openClipboardHistory: { [weak historyPanelController] in
                historyPanelController?.showFromDashboard()
            }
        )
        self.mainPanelController = mainPanelController

        hotKeyManager.onHotKeyPressed = { [weak historyPanelController] in
            Task { @MainActor in
                historyPanelController?.toggle()
            }
        }

        pinWindowHotKeyManager.onHotKeyPressed = { [weak historyPanelController] in
            Task { @MainActor in
                historyPanelController?.togglePinnedFromShortcut()
            }
        }

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        settings.$shortcut
            .removeDuplicates()
            .sink { [weak self, weak hotKeyManager] shortcut in
                guard let self, let hotKeyManager else { return }
                guard !self.isRevertingShortcutRegistrationFailure else { return }

                let previousShortcut = hotKeyManager.registeredShortcut
                let didRegister = hotKeyManager.register(shortcut: shortcut)

                guard !didRegister, let previousShortcut else { return }

                self.isRevertingShortcutRegistrationFailure = true
                self.settings.shortcut = previousShortcut
                self.isRevertingShortcutRegistrationFailure = false
            }
            .store(in: &cancellables)

        clipboardMonitor.start()
        _ = hotKeyManager.register(shortcut: settings.shortcut)
        pinWindowHotKeyManager.register(shortcut: KeyboardShortcut(keyCode: 35, modifiers: [.command, .option]))

        Task { @MainActor in
            await bootstrapAfterLaunch()
        }
    }

    /// 状态栏左键切换主面板。
    func toggleMainPanel() {
        mainPanelController?.toggle()
    }

    private func bootstrapAfterLaunch() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        clipboardStore.bootstrapIfNeeded()
        settingsWindowController.prewarm()
    }
}
