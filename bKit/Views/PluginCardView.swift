//
//  PluginCardView.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 插件卡片视图
import SwiftUI

struct PluginCardView: View {
    @ObservedObject var plugin: BasePlugin

    // 打开设置页中的插件配置。
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: plugin.icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(plugin.isEnabled ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plugin.name)
                        .font(.headline)
                    Spacer()
                    Button("设置") {
                        openSettings()
                    }
                    .buttonStyle(.borderless)
                }

                Text(plugin.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                StatusBadgeView(status: plugin.status)
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
