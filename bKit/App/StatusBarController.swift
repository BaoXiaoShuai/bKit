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
    private var customView: StatusBarCustomView?

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

    /// 配置状态栏图标和鼠标事件，使用自定义视图做 UI 渲染。
    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        button.toolTip = "bKit"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let cView = StatusBarCustomView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        button.addSubview(cView)
        self.customView = cView
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
        let quotaText = getQuotaText()
        let uploadText = getUploadText()
        let downloadText = getDownloadText()

        let showQuota = !quotaText.isEmpty
        let showNetwork = !uploadText.isEmpty || !downloadText.isEmpty
        let showSeparator = showQuota && showNetwork

        let icon = statusBarIconImage()

        guard let button = statusItem.button, let cView = customView else { return }

        // 更新自定义视图的内容和布局
        cView.updateLayout(
            image: icon,
            quotaText: quotaText,
            showQuota: showQuota,
            showSeparator: showSeparator,
            uploadText: uploadText,
            downloadText: downloadText
        )

        // 更新 statusItem 的长度
        statusItem.length = cView.frame.width

        // 更新 tooltip
        let titleParts = statusBarTitleParts()
        let title = titleParts.joined(separator: "  ")
        button.toolTip = statusBarTooltip(title: title)
    }

    private func getQuotaText() -> String {
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

        return parts.joined(separator: "  ")
    }

    private func getUploadText() -> String {
        guard systemMonitorPlugin.isEnabled, systemMonitorPlugin.settings.showStatusBarUpload else { return "" }
        return "↑ " + formatSpeed(systemMonitorPlugin.snapshot.uploadSpeedKBps)
    }

    private func getDownloadText() -> String {
        guard systemMonitorPlugin.isEnabled, systemMonitorPlugin.settings.showStatusBarDownload else { return "" }
        return "↓ " + formatSpeed(systemMonitorPlugin.snapshot.downloadSpeedKBps)
    }

    private func formatSpeed(_ value: Double) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1024 {
            return String(format: "%.1fM", safeValue / 1024)
        }
        if safeValue >= 100 {
            return String(format: "%.0fK", safeValue)
        }
        return String(format: "%.1fK", safeValue)
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

    /// 格式化实时网速，始终使用 %5.1f 输出五位宽字符，配合全等宽字体保证宽度不变。
    private func speedText(_ value: Double) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1024 {
            // MB/s：始终 %5.1f ，输出如 "  1.2" "999.9"
            return String(format: "%5.1fM/s", safeValue / 1024)
        }
        // KB/s：始终 %5.1f，输出如 "  0.0" " 12.8" "100.0"
        return String(format: "%5.1fK/s", safeValue)
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

// 自定义 macOS 状态栏视图，实现 Quota 和 Network 的左右分区与网速上下等宽右对齐排版
private final class StatusBarCustomView: NSView {
    private let iconImageView = NSImageView()
    private let quotaLabel = NSTextField()
    private let separatorView = NSView()
    private let uploadLabel = NSTextField()
    private let downloadLabel = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 返回 nil，允许鼠标事件穿透到父级 NSButton 上触发点击
        return nil
    }

    override func layout() {
        super.layout()
        // 采用和主要文字完全一样的 NSColor.labelColor，并指定 0.35 透明度以自适应明暗主题
        separatorView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.9).cgColor
    }

    private func setupViews() {
        wantsLayer = true

        // 1. 图标配置（wantsLayer + cornerRadius 剪切为圆形图标）
        iconImageView.imageFrameStyle = .none
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 9
        iconImageView.layer?.masksToBounds = true
        addSubview(iconImageView)

        // 2. Quota 文本配置
        setupLabel(quotaLabel)
        quotaLabel.alignment = .left
        quotaLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        quotaLabel.textColor = .labelColor
        addSubview(quotaLabel)

        // 3. 分割线配置
        separatorView.wantsLayer = true
        addSubview(separatorView)

        // 4. 网速配置 (上传/下载均改为左对齐，确保上下箭头对齐)
        setupLabel(uploadLabel)
        uploadLabel.alignment = .left
        uploadLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        uploadLabel.textColor = .labelColor
        addSubview(uploadLabel)

        setupLabel(downloadLabel)
        downloadLabel.alignment = .left
        downloadLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        downloadLabel.textColor = .labelColor
        addSubview(downloadLabel)
    }

    private func setupLabel(_ label: NSTextField) {
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
    }

    func updateLayout(
        image: NSImage?,
        quotaText: String,
        showQuota: Bool,
        showSeparator: Bool,
        uploadText: String,
        downloadText: String
    ) {
        iconImageView.image = image
        quotaLabel.stringValue = quotaText
        quotaLabel.isHidden = !showQuota
        separatorView.isHidden = !showSeparator

        uploadLabel.stringValue = uploadText
        uploadLabel.isHidden = uploadText.isEmpty

        downloadLabel.stringValue = downloadText
        downloadLabel.isHidden = downloadText.isEmpty

        let height = self.bounds.height > 0 ? self.bounds.height : 22
        var currentX: CGFloat = 0

        // 1. 图标布局 (左间距 4pt，右侧 6pt 间距，图标本身 18*18)
        if image != nil {
            iconImageView.frame = NSRect(x: 4, y: (height - 18) / 2, width: 18, height: 18)
            currentX = 28 // 增加图标到右边额度文本之间的距离（从 24 调整为 28）
        } else {
            iconImageView.frame = .zero
            currentX = 4
        }

        // 2. Quota 布局
        if showQuota && !quotaText.isEmpty {
            let size = (quotaText as NSString).size(withAttributes: [.font: quotaLabel.font!])
            // 严格垂直居中，去除 -1 偏置
            quotaLabel.frame = NSRect(x: currentX, y: (height - size.height) / 2 - 0.5, width: size.width + 8, height: size.height)
            currentX += size.width + 10 // 增加 quota 与分割线的间距至 8pt
        }

        // 3. 分割线布局
        if showSeparator {
            separatorView.frame = NSRect(x: currentX, y: (height - 14) / 2 - 0.5, width: 1, height: 14)
            currentX += 8 // 增加分割线与右边网速区的间距至 8pt
        }

        // 4. 网速布局
        let hasUpload = !uploadText.isEmpty
        let hasDownload = !downloadText.isEmpty

        if hasUpload || hasDownload {
            let networkWidth: CGFloat = 52 // 宽度适当调整，因为是左对齐且有固定宽度防抖
            
            if hasUpload && hasDownload {
                // 整体 Y 坐标向上平移 1pt 修正视觉偏差，抵消字体内衬偏下问题
                uploadLabel.frame = NSRect(x: currentX, y: height / 2 + 1, width: networkWidth, height: 11)
                downloadLabel.frame = NSRect(x: currentX, y: 1, width: networkWidth, height: 11)
            } else if hasUpload {
                uploadLabel.frame = NSRect(x: currentX, y: (height - 12) / 2 + 1, width: networkWidth, height: 12)
            } else if hasDownload {
                downloadLabel.frame = NSRect(x: currentX, y: (height - 12) / 2 + 1, width: networkWidth, height: 12)
            }

            currentX += networkWidth + 4 // 留右边界 padding
        } else {
            // 没有网速时
            if !showQuota {
                currentX = 26
            } else {
                currentX -= 2
            }
        }

        // 更新 frame 宽度
        self.frame = NSRect(x: 0, y: 0, width: currentX, height: height)
    }
}
