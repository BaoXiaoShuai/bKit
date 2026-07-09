//
//  MainPanelView.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 主面板视图
import SwiftUI

struct MainPanelView: View {
    @ObservedObject var pluginManager: PluginManager
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var codexQuotaStore: CodexQuotaStore
    @ObservedObject var systemMonitorPlugin: SystemMonitorPlugin

    // 打开设置窗口。
    let openSettings: () -> Void
    // 打开剪切板完整历史窗口。
    let openClipboardHistory: () -> Void
    // 退出应用。
    let quitApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            sectionDivider

            visibleSections
                .padding(.horizontal, 20)
        }
        .frame(width: 440)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(windowOutline)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("bKit")
                    .font(.system(size: 17, weight: .semibold))
                Text("综合工具")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                toolbarIconButton(systemName: "gearshape", action: openSettings)
                toolbarIconButton(systemName: "power", action: quitApp)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(height: 60)
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            moduleHeader(title: "Codex") {
                toolbarIconButton(systemName: "arrow.clockwise", action: {
                    codexQuotaStore.refresh(reason: "main-window")
                }, isDisabled: codexQuotaStore.isRefreshing)
            }

            if let errorMessage = codexQuotaStore.errorMessage, codexQuotaStore.snapshot == nil {
                moduleMessageRow(
                    title: "额度读取失败",
                    detail: errorMessage
                )
            } else if codexQuotaStore.isLoading, codexQuotaStore.snapshot == nil {
                moduleMessageRow(
                    title: "正在读取额度",
                    detail: "首次读取可能需要几秒，请稍等。"
                )
            } else {
                HStack(spacing: 12) {
                    quotaCard(
                        title: "5 小时额度",
                        value: codexQuotaStore.snapshot?.fiveHourWindow.map { codexQuotaStore.formatPercent($0.remainingPercent) } ?? "--",
                        detail: codexQuotaStore.resetText(for: codexQuotaStore.snapshot?.fiveHourWindow),
                        tint: Color(red: 0.28, green: 0.63, blue: 0.54),
                        progress: normalized(codexQuotaStore.snapshot?.fiveHourWindow?.usedPercent ?? 0)
                    )

                    quotaCard(
                        title: "7 天额度",
                        value: codexQuotaStore.snapshot?.weeklyWindow.map { codexQuotaStore.formatPercent($0.remainingPercent) } ?? "--",
                        detail: codexQuotaStore.resetText(for: codexQuotaStore.snapshot?.weeklyWindow),
                        tint: Color(red: 0.34, green: 0.54, blue: 0.86),
                        progress: normalized(codexQuotaStore.snapshot?.weeklyWindow?.usedPercent ?? 0)
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }

    private var systemMonitorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            moduleHeader(title: "系统监控")

            VStack(spacing: 10) {
                // 一行四个圆形进度卡片
                HStack(spacing: 8) {
                    // CPU 占用卡片
                    circleMonitorCard(
                        title: "CPU",
                        progress: systemMonitorPlugin.snapshot.cpuUsagePercent / 100,
                        centerText: "\(Int(systemMonitorPlugin.snapshot.cpuUsagePercent.rounded()))%",
                        usedText: percentText(systemMonitorPlugin.snapshot.cpuUsagePercent),
                        totalText: "100%",
                        tint: Color(red: 0.91, green: 0.55, blue: 0.28)
                    )
                    // 内存占用卡片
                    circleMonitorCard(
                        title: "内存",
                        progress: systemMonitorPlugin.snapshot.memoryTotalGB > 0
                            ? systemMonitorPlugin.snapshot.memoryUsedGB / systemMonitorPlugin.snapshot.memoryTotalGB
                            : 0,
                        centerText: "\(numberText(systemMonitorPlugin.snapshot.memoryUsedGB))G",
                        usedText: "\(numberText(systemMonitorPlugin.snapshot.memoryUsedGB)) GB",
                        totalText: "\(numberText(systemMonitorPlugin.snapshot.memoryTotalGB)) GB",
                        tint: Color(red: 0.34, green: 0.54, blue: 0.86)
                    )
                    // 磁盘占用卡片
                    circleMonitorCard(
                        title: "磁盘",
                        progress: systemMonitorPlugin.snapshot.diskTotalGB > 0
                            ? systemMonitorPlugin.snapshot.diskUsedGB / systemMonitorPlugin.snapshot.diskTotalGB
                            : 0,
                        centerText: "\(Int(systemMonitorPlugin.snapshot.diskUsagePercent.rounded()))%",
                        usedText: "\(numberText(systemMonitorPlugin.snapshot.diskUsedGB)) GB",
                        totalText: "\(numberText(systemMonitorPlugin.snapshot.diskTotalGB)) GB",
                        tint: Color(red: 0.28, green: 0.63, blue: 0.54)
                    )
                    // 温度卡片，以 100°C 为满值
                    circleMonitorCard(
                        title: "温度",
                        progress: min(1.0, (systemMonitorPlugin.snapshot.temperatureCelsius ?? 0) / 100.0),
                        centerText: systemMonitorPlugin.snapshot.temperatureCelsius
                            .map { "\(Int($0.rounded()))°" } ?? "--",
                        usedText: temperatureText(systemMonitorPlugin.snapshot.temperatureCelsius),
                        totalText: "100 °C",
                        tint: Color(red: 0.86, green: 0.38, blue: 0.34)
                    )
                }

                // 实时网速 + 风扇转速 一行两个卡片
                systemMonitorBottomRow
            }
        }
        .padding(.vertical, 16)
    }

    /// 实时网速 + 风扇转速 信息卡片行。
    private var systemMonitorBottomRow: some View {
        HStack(spacing: 8) {
            // 实时网速卡片
            miniNetCard
            // 风扇转速卡片
            miniFanCard
        }
    }

    /// 圆形进度卡片：标题和数值均内嵌于圆璯中。
    private func circleMonitorCard(
        title: String,
        // 进度 0.0-1.0
        progress: Double,
        // 圆心显示的简短数值文字
        centerText: String,
        // 已用数值
        usedText: String,
        // 总量数值
        totalText: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 0) {
            // 圆形进度，标题和数值均显示在圆内
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: progress)

                VStack(spacing: 2) {
                    // 圆内标题（小字次要信息）
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    // 圆内主数值
                    Text(centerText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 66, height: 66)

            // 已用 / 总量，与圆形有间距
            VStack(spacing: 3) {
                Text(usedText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(totalText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
        )
    }

    /// 实时网速微型卡片：上行 + 下行双色展示。
    private var miniNetCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("实时网速")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text(compactSpeedText(systemMonitorPlugin.snapshot.uploadSpeedKBps))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(red: 0.19, green: 0.47, blue: 0.92))

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(compactSpeedText(systemMonitorPlugin.snapshot.downloadSpeedKBps))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(red: 0.28, green: 0.63, blue: 0.54))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
        )
    }

    /// 风扇转速微型卡片：展示当前转速。
    private var miniFanCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("风扇转速")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(fanSpeedText(systemMonitorPlugin.snapshot.fanSpeedRPM))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
        )
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleHeader(title: "剪切板") {
                Button {
                    openClipboardHistory()
                } label: {
                    Text("查看全部 >")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                if recentClipboardItems.isEmpty {
                    Text("暂无剪切板记录")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(recentClipboardItems.indices, id: \.self) { index in
                        let item = recentClipboardItems[index]

                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("📄")
                                    .font(.system(size: 13))

                                Text(item.previewText)
                                    .font(.system(size: 13, weight: .regular))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 12)

                                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 11)

                            if index < recentClipboardItems.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var visibleSections: some View {
        let visiblePluginIDs = pluginManager.plugins.filter(\.isEnabled).map(\.id)
        let hasCodex = visiblePluginIDs.contains("codex-quota")
        let hasSystemMonitor = visiblePluginIDs.contains("system-monitor")
        let hasClipboard = visiblePluginIDs.contains("clipboard")

        if hasCodex {
            codexSection
        }

        if hasCodex && (hasSystemMonitor || hasClipboard) {
            sectionDivider
        }

        if hasSystemMonitor {
            systemMonitorSection
        }

        if hasSystemMonitor && hasClipboard {
            sectionDivider
        }

        if hasClipboard {
            clipboardSection
        }

        if !hasCodex && !hasSystemMonitor && !hasClipboard {
            emptyStateSection
        }
    }

    /// 统一模块标题行，收敛成 macOS 工具窗口的轻量层级。
    private func moduleHeader<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            Spacer()
            trailing()
        }
    }

    private func moduleHeader(title: String) -> some View {
        moduleHeader(title: title) {
            EmptyView()
        }
    }

    /// 额度小卡片只保留必要信息，避免出现网页 Dashboard 的重背景块。
    private func quotaCard(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            // 剩余 < 10% 时显示红色警示
            let isLow = progress > 0.9
            let warningColor = Color(red: 0.92, green: 0.28, blue: 0.28)

            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isLow ? warningColor : .primary)

            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(isLow ? warningColor : tint)
                            .frame(width: proxy.size.width * progress, height: 3)
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    /// 系统监控四列指标使用更紧凑的卡片，单条数据为主。
    private func compactMonitorCard(
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
        )
    }

    /// 统一工具栏按钮样式，保持 footer 和 header 的原生感。
    private func toolbarIconButton(
        systemName: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.16))

                if isDisabled && systemName == "arrow.clockwise" {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
    }

    private var windowBackground: some View {
        ZStack {
            GlassBackground()
            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.10),
                    Color(red: 0.93, green: 0.97, blue: 0.95).opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var windowOutline: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
    }

    private var recentClipboardItems: [ClipboardItem] {
        Array(clipboardStore.items.prefix(3))
    }

    private func moduleMessageRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无已启用模块")
                .font(.system(size: 13, weight: .medium))
            Text("可前往设置界面启用需要展示的插件。")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    private func normalized(_ percent: Double) -> Double {
        max(0, min(1, percent / 100))
    }

    private func percentText(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    private func numberText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func speedText(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.1f MB/s", value / 1024)
        }
        return String(format: "%.1f KB/s", value)
    }

    private func speedPairText(upload: Double, download: Double) -> String {
        "↑\(compactSpeedText(upload)) ↓\(compactSpeedText(download))"
    }

    private func compactSpeedText(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.1fM", value / 1024)
        }
        return String(format: "%.1fK", value)
    }

    private func temperatureText(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.1f°C", value)
    }

    private func fanSpeedText(_ value: Double?) -> String {
        guard let value else {
            return "-- RPM"
        }
        return "\(Int(value.rounded())) RPM"
    }

}

