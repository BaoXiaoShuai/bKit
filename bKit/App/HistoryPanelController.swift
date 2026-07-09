//
//  HistoryPanelController.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import SwiftUI

@MainActor
final class HistoryPanelController {
    private let store: ClipboardStore
    private let settings: SettingsStore
    private let pasteCoordinator: PasteCoordinator
    private let openSettings: () -> Void
    private var panel: HistoryPanel?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private var isPinned = false
    private var isPresentingModalUI = false

    init(
        store: ClipboardStore,
        settings: SettingsStore,
        pasteCoordinator: PasteCoordinator,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.pasteCoordinator = pasteCoordinator
        self.openSettings = openSettings
    }

    func toggle() {
        // 如果历史面板已经显示，就隐藏；
        // 否则创建或展示它。
        if let panel, panel.isVisible {
            hide(resetPin: true)
        } else {
            show()
        }
    }

    func toggle(from statusItem: NSStatusItem?) {
        if let panel, panel.isVisible {
            hide(resetPin: true)
        } else {
            show(from: statusItem)
        }
    }

    func togglePinnedFromShortcut() {
        let panel = self.panel ?? makePanel()

        if !panel.isVisible {
            show()
            if isPinned { return }
        }

        togglePin()
    }

    /// 从主窗口主动展示剪切板历史面板，不改变现有快捷键与置顶逻辑。
    func showFromDashboard() {
        show()
    }

    private func show() {
        show(from: nil)
    }

    private func show(from statusItem: NSStatusItem?) {
        // 打开历史面板前记住当前前台应用，方便回车后切回去执行粘贴。
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = self.panel ?? makePanel()
        updatePanelBehavior(panel)
        panel.contentView = makeContentView(for: panel)
        if let statusItem {
            positionPanel(panel, relativeTo: statusItem)
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> HistoryPanel {
        // 使用 NSPanel 而不是普通 NSWindow，
        // 更适合这种“临时弹出、失焦即隐藏”的工具窗口。
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 420, height: 480)
        updatePanelBehavior(panel)

        panel.contentView = makeContentView(for: panel)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            // 历史面板失去焦点时自动隐藏，保持使用体验像 Spotlight 一样轻。
            Task { @MainActor [weak self, weak panel] in
                guard let self, !self.isPinned, !self.isPresentingModalUI else { return }
                guard panel === self.panel else { return }
                self.hidePanel(resetPin: false)
            }
        }

        self.panel = panel
        return panel
    }

    private func makeContentView(for panel: HistoryPanel) -> NSHostingView<ClipboardHistoryView> {
        NSHostingView(
            rootView: ClipboardHistoryView(
                store: store,
                settings: settings,
                close: { [weak self] in
                    self?.hide(resetPin: true)
                },
                isPinned: isPinned,
                togglePin: { [weak self] in
                    self?.togglePin()
                },
                restoreAndPaste: { [weak self, weak panel] item in
                    self?.pasteCoordinator.restoreAndPaste(item, targetApp: self?.previousApp)
                    if self?.isPinned != true {
                        guard let self, let panel, panel === self.panel else { return }
                        self.hidePanel(resetPin: false)
                    }
                },
                openSettings: openSettings,
                clearHistory: { [weak store] in
                    store?.clearAll()
                },
                setModalPresentation: { [weak self] isPresented in
                    self?.isPresentingModalUI = isPresented
                }
            )
        )
    }

    private func togglePin() {
        isPinned.toggle()
        guard let panel else { return }
        updatePanelBehavior(panel)
        panel.contentView = makeContentView(for: panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide(resetPin: Bool) {
        hidePanel(resetPin: resetPin)
    }

    // 统一隐藏历史面板，并释放 SwiftUI 内容视图，让键盘监听等生命周期资源及时清理。
    // resetPin 表示是否在手动关闭时同步取消窗口置顶状态。
    private func hidePanel(resetPin: Bool) {
        guard let panel else { return }

        // 手动关闭面板时，同时取消置顶状态。
        // 这样下次重新打开时，总是回到默认的非置顶行为。
        if resetPin && isPinned {
            isPinned = false
            updatePanelBehavior(panel)
        }

        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func updatePanelBehavior(_ panel: HistoryPanel) {
        // 图钉开启时，窗口变成真正的顶层常驻面板：
        // 1. 不因应用失焦自动隐藏
        // 2. 窗口层级提升到 statusBar
        // 3. 可以跨空间保持显示
        panel.level = isPinned ? .statusBar : .floating
        panel.hidesOnDeactivate = !isPinned
        panel.collectionBehavior = isPinned
        ? [.canJoinAllSpaces, .fullScreenAuxiliary]
        : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    private func positionPanel(_ panel: HistoryPanel, relativeTo statusItem: NSStatusItem) {
        guard
            let button = statusItem.button,
            let window = button.window,
            let screenFrame = window.screen?.visibleFrame
        else {
            panel.center()
            return
        }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = window.convertToScreen(buttonFrame)
        let panelSize = panel.frame.size

        var originX = buttonFrameInScreen.midX - panelSize.width / 2
        originX = max(screenFrame.minX + 12, min(originX, screenFrame.maxX - panelSize.width - 12))

        let originY = buttonFrameInScreen.minY - panelSize.height - 8
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
