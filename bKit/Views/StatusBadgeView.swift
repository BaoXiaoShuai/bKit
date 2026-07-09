//
//  StatusBadgeView.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 状态标签视图
import SwiftUI

struct StatusBadgeView: View {
    let status: PluginStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusText: String {
        if let detail = status.detail {
            return "\(status.title)：\(detail)"
        }

        return status.title
    }

    private var statusColor: Color {
        switch status {
        case .running:
            return .green
        case .stopped:
            return .gray
        case .error:
            return .red
        case .unavailable:
            return .orange
        }
    }
}
