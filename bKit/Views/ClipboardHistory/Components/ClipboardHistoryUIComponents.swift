//
//  ClipboardHistoryUIComponents.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import SwiftUI

// 这个文件放历史窗口会复用的轻量 UI 组件和样式。
// 它们只关心外观和基础交互，不处理业务状态流转。

extension Color {
    // 主色和当前选中态保持同一套浅蓝，方便整窗状态统一。
    static let historyPrimary = Color(red: 0.24, green: 0.58, blue: 0.98)
}

struct HeaderIconLabel: View {
    let systemName: String
    var isActive: Bool = false
    var activeIconColor: Color = .primary
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color.black.opacity(0.08)
        }

        if isActive {
            return Color.historyPrimary.opacity(0.12)
        }

        return .clear
    }

    private var iconColor: Color {
        isActive ? activeIconColor : .primary
    }
}

struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeaderIconButton(configuration: configuration)
    }
}

private struct HeaderIconButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundColor)
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.black.opacity(0.14)
        }

        if isHovered {
            return Color.black.opacity(0.08)
        }

        return .clear
    }
}

struct PopoverMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PopoverMenuButtonBody(configuration: configuration)
    }
}

private struct PopoverMenuButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .foregroundStyle(Color.primary)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.historyPrimary.opacity(0.16)
        }

        if isHovered {
            return Color.historyPrimary.opacity(0.12)
        }

        return .clear
    }
}

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
