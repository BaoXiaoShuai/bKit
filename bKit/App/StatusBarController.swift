//
//  StatusBarController.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 状态栏能力
import AppKit
// Combine 状态订阅能力
import Combine

@MainActor
final class StatusBarController: NSObject {
    let statusItem: NSStatusItem

    private let onLeftClick: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let codexQuotaPlugin: CodexQuotaPlugin
    private let codexQuotaStore: CodexQuotaStore
    private let systemMonitorPlugin: SystemMonitorPlugin
    private var cancellables: Set<AnyCancellable> = []

    init(
        codexQuotaPlugin: CodexQuotaPlugin,
        codexQuotaStore: CodexQuotaStore,
        systemMonitorPlugin: SystemMonitorPlugin,
        onLeftClick: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.codexQuotaPlugin = codexQuotaPlugin
        self.codexQuotaStore = codexQuotaStore
        self.systemMonitorPlugin = systemMonitorPlugin
        self.onLeftClick = onLeftClick
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()
        setupStatusItem()
        bindStatusBarContent()
    }

    /// 配置状态栏图标和鼠标事件，分别接收左键与右键释放事件。
    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = statusBarIconImage()
        button.imagePosition = .imageLeading
        button.toolTip = "bKit"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// 订阅额度、网速和展示配置变化，统一刷新状态栏展示内容。
    private func bindStatusBarContent() {
        codexQuotaStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefreshStatusBarContent()
                }
            }
            .store(in: &cancellables)

        codexQuotaStore.settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefreshStatusBarContent()
                }
            }
            .store(in: &cancellables)

        codexQuotaPlugin.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefreshStatusBarContent()
                }
            }
            .store(in: &cancellables)

        systemMonitorPlugin.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefreshStatusBarContent()
                }
            }
            .store(in: &cancellables)

        systemMonitorPlugin.settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefreshStatusBarContent()
                }
            }
            .store(in: &cancellables)

        refreshStatusBarContent()
    }

    /// 延迟到主线程下一轮刷新状态栏，避免读取到 @Published 写入前的旧值。
    private func scheduleRefreshStatusBarContent() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshStatusBarContent()
        }
    }

    /// 根据当前开关和数据源生成状态栏标题和悬浮提示。
    private func refreshStatusBarContent() {
        let titleParts = statusBarTitleParts()
        let title = titleParts.joined(separator: "  ")

        statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        guard let button = statusItem.button else { return }

        button.image = statusBarIconImage()
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = statusBarTooltip(title: title)
    }

    /// 读取应用 logo 作为状态栏图标，资源缺失时回退到系统图标。
    private func statusBarIconImage() -> NSImage? {
        if let image = NSImage(named: "BrandLogo") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        return NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "bKit")
    }

    /// 组装状态栏标题片段，返回结果为空时只展示应用图标。
    private func statusBarTitleParts() -> [String] {
        var parts: [String] = []
        let quotaSettings = codexQuotaStore.settings

        if codexQuotaPlugin.isEnabled, quotaSettings.showFiveHour {
            let percent = codexQuotaStore.snapshot?.fiveHourWindow.map { codexQuotaStore.formatPercent($0.remainingPercent) } ?? "--"
            parts.append("5h \(percent)")
        }

        if codexQuotaPlugin.isEnabled, quotaSettings.showWeekly {
            let percent = codexQuotaStore.snapshot?.weeklyWindow.map { codexQuotaStore.formatPercent($0.remainingPercent) } ?? "--"
            parts.append("7d \(percent)")
        }

        if codexQuotaPlugin.isEnabled, quotaSettings.showSummary {
            parts.append(codexQuotaStore.pace.summary.title)
        }

        if systemMonitorPlugin.isEnabled, systemMonitorPlugin.settings.showStatusBarUpload {
            parts.append("↑ \(speedText(systemMonitorPlugin.snapshot.uploadSpeedKBps))")
        }

        if systemMonitorPlugin.isEnabled, systemMonitorPlugin.settings.showStatusBarDownload {
            parts.append("↓ \(speedText(systemMonitorPlugin.snapshot.downloadSpeedKBps))")
        }

        return parts
    }

    /// 生成状态栏悬浮提示，补充重置时间等不适合常驻占位的信息。
    private func statusBarTooltip(title: String) -> String {
        var lines = ["bKit"]
        if !title.isEmpty {
            lines.append(title)
        }

        if codexQuotaPlugin.isEnabled, codexQuotaStore.settings.showResetTime {
            if codexQuotaStore.settings.showFiveHour {
                lines.append("5 小时额度：\(codexQuotaStore.resetText(for: codexQuotaStore.snapshot?.fiveHourWindow))")
            }
            if codexQuotaStore.settings.showWeekly {
                lines.append("7 天额度：\(codexQuotaStore.resetText(for: codexQuotaStore.snapshot?.weeklyWindow))")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// 格式化实时网速，按数值大小自动切换 KB/s 和 MB/s。
    private func speedText(_ value: Double) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1024 {
            return String(format: "%.1fMB/s", safeValue / 1024)
        }
        if safeValue >= 100 {
            return "\(Int(safeValue.rounded()))KB/s"
        }
        return String(format: "%.1fKB/s", safeValue)
    }

    /// 根据当前鼠标事件类型分发左键和右键动作。
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onLeftClick()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            onLeftClick()
        }
    }

    /// 右键状态栏图标时弹出菜单，承载设置和退出入口。
    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置", action: #selector(handleOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(handleQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
