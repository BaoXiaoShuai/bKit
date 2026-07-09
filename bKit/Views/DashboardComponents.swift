//
//  DashboardComponents.swift
//  bKit
//
//  Created by Codex on 2026/7/8.
//

// SwiftUI 原生界面组件
import SwiftUI

/// Dashboard 通用卡片容器，统一主窗口模块的圆角、描边和标题结构。
struct DashboardCardContainer<HeaderTrailing: View, Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                headerTrailing
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.48),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.46), lineWidth: 0.8)
    }
}

/// Dashboard 指标小卡片，用于额度、CPU、内存等紧凑型展示。
struct DashboardMetricCard<Footer: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let progress: Double?
    @ViewBuilder let footer: Footer

    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        progress: Double? = nil,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.progress = progress
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()

            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let progress {
                DashboardProgressBar(progress: progress, tint: tint)
            }

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.9)
        )
    }
}

extension DashboardMetricCard where Footer == EmptyView {
    init(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        progress: Double? = nil
    ) {
        self.init(
            title: title,
            value: value,
            detail: detail,
            tint: tint,
            progress: progress
        ) {
            EmptyView()
        }
    }
}

/// Dashboard 横向指标行，适合系统信息摘要。
struct DashboardMetricRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }
}

/// Dashboard 通用进度条，避免不同卡片样式漂移。
struct DashboardProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(proxy.size.width, proxy.size.width * progress))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: width)
            }
        }
        .frame(height: 6)
    }
}
