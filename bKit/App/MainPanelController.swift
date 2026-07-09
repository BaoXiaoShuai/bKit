//
//  MainPanelController.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 面板窗口能力
import AppKit
// SwiftUI 视图承载能力
import SwiftUI

@MainActor
final class MainPanelController: NSObject, NSPopoverDelegate {
    private weak var statusItem: NSStatusItem?
    private let popover: NSPopover
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private let systemMonitorPlugin: SystemMonitorPlugin

    init(
        statusItem: NSStatusItem,
        pluginManager: PluginManager,
        clipboardStore: ClipboardStore,
        codexQuotaStore: CodexQuotaStore,
        systemMonitorPlugin: SystemMonitorPlugin,
        openSettings: @escaping () -> Void,
        openClipboardHistory: @escaping () -> Void
    ) {
        self.statusItem = statusItem
        self.systemMonitorPlugin = systemMonitorPlugin
        popover = NSPopover()

        super.init()

        let contentView = MainPanelView(
            pluginManager: pluginManager,
            clipboardStore: clipboardStore,
            codexQuotaStore: codexQuotaStore,
            systemMonitorPlugin: systemMonitorPlugin,
            openSettings: openSettings,
            openClipboardHistory: { [weak self] in
                self?.hide()
                openClipboardHistory()
            },
            quitApp: {
                NSApplication.shared.terminate(nil)
            }
        )

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 440, height: 560)
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    /// 切换主面板显示状态。
    func toggle() {
        if popover.isShown {
            hide()
        } else {
            show()
        }
    }

    /// 显示主面板，并把弹层锚定在状态栏按钮下方。
    func show() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        installDismissMonitors()
        NSApp.activate(ignoringOtherApps: true)
        
        // 标记面板展开，激活后台系统级核心监控指标的采集
        systemMonitorPlugin.isPanelOpen = true
    }

    /// 隐藏主面板。
    func hide() {
        removeDismissMonitors()
        popover.performClose(nil)
        
        // 标记面板隐藏，停止非必要的系统级监控采集
        systemMonitorPlugin.isPanelOpen = false
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissMonitors()
        
        // 标记面板隐藏，停止非必要的系统级监控采集
        systemMonitorPlugin.isPanelOpen = false
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hide()
                return nil
            }

            guard let popoverWindow = self.popover.contentViewController?.view.window else {
                return event
            }

            if let eventWindow = event.window, eventWindow == popoverWindow {
                return event
            }

            self.hide()
            return event
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeDismissMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }
}
