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

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    compactMonitorCard(
                        title: "CPU 温度",
                        value: temperatureText(systemMonitorPlugin.snapshot.temperatureCelsius),
                        tint: Color(red: 0.91, green: 0.55, blue: 0.28),
                        showsTrend: false
                    )

                    compactMonitorCard(
                        title: "风扇转速",
                        value: fanSpeedText(systemMonitorPlugin.snapshot.fanSpeedRPM),
                        tint: .secondary,
                        showsTrend: false
                    )

                    compactMonitorCard(
                        title: "磁盘占用",
                        value: percentText(systemMonitorPlugin.snapshot.diskUsagePercent),
                        tint: Color(red: 0.28, green: 0.63, blue: 0.54),
                        showsTrend: false
                    )
                }

                systemMonitorSummaryPanel
            }
        }
        .padding(.vertical, 16)
    }

    private var systemMonitorSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text("可用 \(numberText(max(0, systemMonitorPlugin.snapshot.diskTotalGB - systemMonitorPlugin.snapshot.diskUsedGB))) GB / 共 \(numberText(systemMonitorPlugin.snapshot.diskTotalGB)) GB")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text(speedText(systemMonitorPlugin.snapshot.uploadSpeedKBps))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(red: 0.19, green: 0.47, blue: 0.92))

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(speedText(systemMonitorPlugin.snapshot.downloadSpeedKBps))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(red: 0.10, green: 0.78, blue: 0.56))
                }

                Spacer()
            }

            NetworkTrendPanel(
                uploadSamples: systemMonitorPlugin.snapshot.uploadHistoryKBps,
                downloadSamples: systemMonitorPlugin.snapshot.downloadHistoryKBps
            )
                .frame(height: 96)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
        )
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleHeader(title: "剪切板")

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

            Button {
                openClipboardHistory()
            } label: {
                Text("查看全部 >")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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

            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()

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
                            .fill(tint)
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
        tint: Color,
        showsTrend: Bool = true
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

            if showsTrend {
                TrendPlaceholderLine(tint: tint)
                    .frame(height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: showsTrend ? 74 : 58, alignment: .leading)
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

/// 系统监控趋势线占位，后续真实数据接入后可直接替换点位。
private struct TrendPlaceholderLine: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height

                path.move(to: CGPoint(x: 0, y: height * 0.72))
                path.addLine(to: CGPoint(x: width * 0.18, y: height * 0.66))
                path.addLine(to: CGPoint(x: width * 0.33, y: height * 0.70))
                path.addLine(to: CGPoint(x: width * 0.51, y: height * 0.48))
                path.addLine(to: CGPoint(x: width * 0.68, y: height * 0.56))
                path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.34))
                path.addLine(to: CGPoint(x: width, y: height * 0.40))
            }
            .stroke(tint.opacity(0.92), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

/// 网络测速趋势占位图，后续真实采样接入后可直接替换点位序列。
private struct NetworkTrendPanel: View {
    let uploadSamples: [Double]
    let downloadSamples: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let dividerY = height * 0.5

            ZStack {
                Divider()
                    .overlay(Color.primary.opacity(0.035))
                    .offset(y: dividerY - height / 2)

                NetworkHalfAreaShape(
                    samples: uploadSamples,
                    range: 0...(dividerY - 6),
                    direction: .up
                )
                .fill(Color(red: 0.19, green: 0.47, blue: 0.92).opacity(0.14))

                SmoothNetworkLineShape(
                    samples: uploadSamples,
                    range: 0...(dividerY - 6),
                    direction: .up
                )
                .stroke(Color(red: 0.19, green: 0.47, blue: 0.92), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                NetworkHalfAreaShape(
                    samples: downloadSamples,
                    range: (dividerY + 6)...height,
                    direction: .down
                )
                .fill(Color(red: 0.10, green: 0.78, blue: 0.56).opacity(0.14))

                SmoothNetworkLineShape(
                    samples: downloadSamples,
                    range: (dividerY + 6)...height,
                    direction: .down
                )
                .stroke(Color(red: 0.10, green: 0.78, blue: 0.56), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .animation(.easeInOut(duration: 0.95), value: uploadSamples)
            .animation(.easeInOut(duration: 0.95), value: downloadSamples)
        }
    }
}

private enum NetworkTrendDirection {
    case up
    case down
}

private struct NetworkHalfLineShape: Shape {
    let samples: [Double]
    let range: ClosedRange<CGFloat>
    let direction: NetworkTrendDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = makePoints(in: rect)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func makePoints(in rect: CGRect) -> [CGPoint] {
        let values = samples.isEmpty ? [0] : samples
        let maxValue = max(values.max() ?? 0, 1)
        let width = rect.width
        let height = range.upperBound - range.lowerBound
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            let normalized = CGFloat(value / maxValue)
            let x = CGFloat(index) * step
            let y: CGFloat

            switch direction {
            case .up:
                y = range.upperBound - (normalized * height)
            case .down:
                y = range.lowerBound + (normalized * height)
            }

            return CGPoint(x: x, y: y)
        }
    }
}

private struct SmoothNetworkLineShape: Shape {
    let samples: [Double]
    let range: ClosedRange<CGFloat>
    let direction: NetworkTrendDirection

    func path(in rect: CGRect) -> Path {
        let points = makePoints(in: rect)
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)

        guard points.count > 1 else {
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }

        if let last = points.last {
            path.addQuadCurve(to: last, control: last)
        }

        return path
    }

    private func makePoints(in rect: CGRect) -> [CGPoint] {
        let values = samples.isEmpty ? [0] : samples
        let maxValue = max(values.max() ?? 0, 1)
        let width = rect.width
        let height = range.upperBound - range.lowerBound
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            let normalized = CGFloat(value / maxValue)
            let x = CGFloat(index) * step
            let y: CGFloat

            switch direction {
            case .up:
                y = range.upperBound - (normalized * height)
            case .down:
                y = range.lowerBound + (normalized * height)
            }

            return CGPoint(x: x, y: y)
        }
    }
}

private struct NetworkHalfAreaShape: Shape {
    let samples: [Double]
    let range: ClosedRange<CGFloat>
    let direction: NetworkTrendDirection

    func path(in rect: CGRect) -> Path {
        let line = NetworkHalfLineShape(samples: samples, range: range, direction: direction)
        let points = linePathPoints(in: rect)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        switch direction {
        case .up:
            path.addLine(to: CGPoint(x: last.x, y: range.upperBound))
            path.addLine(to: CGPoint(x: first.x, y: range.upperBound))
        case .down:
            path.addLine(to: CGPoint(x: last.x, y: range.lowerBound))
            path.addLine(to: CGPoint(x: first.x, y: range.lowerBound))
        }

        path.closeSubpath()
        return path
    }

    private func linePathPoints(in rect: CGRect) -> [CGPoint] {
        let values = samples.isEmpty ? [0] : samples
        let maxValue = max(values.max() ?? 0, 1)
        let width = rect.width
        let height = range.upperBound - range.lowerBound
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            let normalized = CGFloat(value / maxValue)
            let x = CGFloat(index) * step
            let y: CGFloat

            switch direction {
            case .up:
                y = range.upperBound - (normalized * height)
            case .down:
                y = range.lowerBound + (normalized * height)
            }

            return CGPoint(x: x, y: y)
        }
    }
}
