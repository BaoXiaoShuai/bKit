//
//  CodexQuotaOverviewSection.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// macOS 毛玻璃视图
import AppKit
// SwiftUI 界面框架
import SwiftUI

struct CodexQuotaOverviewSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: CodexQuotaStore

    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(18)
        .background(sectionBackground)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 额度")
                    .font(.system(size: 20, weight: .semibold))
                Text(store.lastUpdatedText())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh(reason: "main-window")
            } label: {
                ZStack {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.54))
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("刷新额度")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = store.errorMessage, store.snapshot == nil {
            errorState(message: errorMessage)
        } else if store.isLoading, store.snapshot == nil {
            loadingState
        } else {
            quotaGrid
        }
    }

    private var quotaGrid: some View {
        VStack(spacing: 10) {
            QuotaCardView(
                title: "5 小时额度",
                subtitle: store.resetText(for: store.snapshot?.fiveHourWindow),
                iconName: "clock.fill",
                window: store.snapshot?.fiveHourWindow,
                accent: Color(red: 0.35, green: 0.70, blue: 0.54),
                store: store
            )

            QuotaCardView(
                title: "7 天额度",
                subtitle: store.resetText(for: store.snapshot?.weeklyWindow),
                iconName: "calendar",
                window: store.snapshot?.weeklyWindow,
                accent: Color(red: 0.38, green: 0.58, blue: 0.86),
                store: store
            )

            HStack(spacing: 10) {
                StatusBadgeChip(title: store.pace.summary.title, color: paceColor(store.pace.summary))
                Spacer()
                Button("更多设置") {
                    openSettings()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在读取 Codex 额度")
                    .font(.system(size: 14, weight: .semibold))
                Text("首次读取可能需要几秒，请稍等。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(GlassPanelBackground(cornerRadius: 6, material: .contentBackground, tintOpacity: 0.28, strokeOpacity: 0.26))
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("额度读取失败")
                    .font(.system(size: 15, weight: .semibold))
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("重试") {
                    store.refresh(reason: "error-retry")
                }
                .buttonStyle(.borderedProminent)

                Button("打开设置") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(GlassPanelBackground(cornerRadius: 6, material: .contentBackground, tintOpacity: 0.28, strokeOpacity: 0.26))
    }

    private var sectionBackground: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.55), lineWidth: 0.8)
        )
    }

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.12, green: 0.15, blue: 0.18).opacity(0.88),
                Color(red: 0.26, green: 0.36, blue: 0.48).opacity(0.30),
                Color(red: 0.28, green: 0.48, blue: 0.40).opacity(0.18)
            ]
        }
        return [
            Color(red: 0.97, green: 0.99, blue: 1.0),
            Color(red: 0.84, green: 0.93, blue: 1.0).opacity(0.66),
            Color(red: 0.82, green: 0.96, blue: 0.90).opacity(0.58)
        ]
    }

    private func paceColor(_ status: PaceStatus) -> Color {
        switch status {
        case .accelerate:
            return Color(red: 0.35, green: 0.70, blue: 0.54)
        case .normal:
            return Color(red: 0.38, green: 0.58, blue: 0.86)
        case .recentFast:
            return Color.orange
        case .slow:
            return Color(red: 0.83, green: 0.48, blue: 0.22)
        case .critical:
            return Color.red
        case .unknown:
            return Color.gray
        }
    }
}

private struct StatusBadgeChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
                    .overlay(Capsule().stroke(color.opacity(0.18), lineWidth: 0.7))
            )
    }
}

private struct QuotaCardView: View {
    let title: String
    let subtitle: String
    let iconName: String
    let window: QuotaWindow?
    let accent: Color
    let store: CodexQuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.15))
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(window.map { store.formatPercent($0.remainingPercent) } ?? "--")
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(window.map { "已用 \(store.formatPercent($0.usedPercent))" } ?? "已用 --")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.12))
                                .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.7))
                        )
                }
                .frame(minWidth: 104, idealWidth: 104, maxWidth: 104, minHeight: 52, alignment: .trailing)
                .offset(y: -4)
            }
            .frame(minHeight: 52, alignment: .center)

            QuotaProgressView(
                usedPercent: window?.usedPercent ?? 0,
                accent: accent
            )

            HStack(spacing: 8) {
                FadingDivider(fadeEnd: .leading)
                Text(remainingDurationText)
                    .font(.system(size: 11, weight: .semibold))
                FadingDivider(fadeEnd: .trailing)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
        .padding(14)
        .background(GlassPanelBackground(cornerRadius: 6, material: .contentBackground, tintOpacity: 0.28, strokeOpacity: 0.26))
    }

    private var remainingDurationText: String {
        guard let resetsAt = window?.resetsAt else {
            return "约 --"
        }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(Date())))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 {
            return "约 \(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "约 \(hours) 小时 \(minutes) 分钟"
        }
        return "约 \(minutes) 分钟"
    }
}

private struct QuotaProgressView: View {
    let usedPercent: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let safeUsedPercent = min(max(usedPercent, 0), 100)
            let progressWidth = max(6, width * safeUsedPercent / 100)
            let isWarning = safeUsedPercent >= 90
            let barColors: [Color] = isWarning
                ? [Color(red: 0.95, green: 0.25, blue: 0.20).opacity(0.75), Color(red: 0.85, green: 0.10, blue: 0.10)]
                : [accent.opacity(0.50), accent.opacity(0.90)]

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: barColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: progressWidth)
                    .mask(Capsule().frame(width: progressWidth))
            }
        }
        .frame(height: 9)
    }
}

private struct FadingDivider: View {
    var fadeEnd: UnitPoint

    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.30))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .mask(
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: fadeEnd == .leading ? .trailing : .leading,
                    endPoint: fadeEnd
                )
            )
    }
}

private struct GlassPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let tintOpacity: Double
    let strokeOpacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .background(
                VisualEffectView(material: material, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(effectiveTintOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(effectiveStrokeOpacity), lineWidth: 0.8)
            )
    }

    private var effectiveTintOpacity: Double {
        colorScheme == .dark ? min(tintOpacity, 0.10) : tintOpacity
    }

    private var effectiveStrokeOpacity: Double {
        colorScheme == .dark ? min(strokeOpacity, 0.16) : strokeOpacity
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
