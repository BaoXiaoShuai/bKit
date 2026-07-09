//
//  ClipboardHistoryChromeViews.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import SwiftUI

// 这个文件承接历史主窗口的“外壳”视图：
// 1. 顶部搜索和操作区
// 2. 底部状态栏
// 3. 过滤/操作菜单内容
// 这些区域和主页面关系很紧，但不直接负责数据流调度。

enum ClipboardHistoryContentFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case link
    case color
    case file
    case folder

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .link:
            return "link"
        case .color:
            return "paintpalette"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        }
    }
}

struct ClipboardHistoryHeaderView: View {
    @Binding var query: String
    @Binding var isShowingFilterMenu: Bool
    @Binding var isShowingActionsMenu: Bool
    @Binding var isShowingPinHint: Bool
    @Binding var filterButtonFrame: CGRect
    @Binding var actionsButtonFrame: CGRect
    @Binding var pinButtonFrame: CGRect

    let localizer: Localizer
    let isCapturePaused: Bool
    let isPinned: Bool
    let filter: ClipboardHistoryContentFilter
    let searchFocus: FocusState<Bool>.Binding
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(localizer.historySearchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused(searchFocus)

            if isCapturePaused {
                Text(localizer.historyPausedBadge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                    )
            }

            Spacer()

            HStack(spacing: 6) {
                dropdownButton(
                    systemName: filter.iconName,
                    helpText: localizer.historyFilterButton,
                    isActive: filter != .all || isShowingFilterMenu,
                    activeIconColor: filter != .all ? .historyPrimary : .primary,
                    isPresented: $isShowingFilterMenu,
                    dismissOtherMenu: { isShowingActionsMenu = false },
                    frame: $filterButtonFrame
                )

                dropdownButton(
                    systemName: "gearshape",
                    helpText: localizer.historyActionsButton,
                    isActive: isShowingActionsMenu,
                    isPresented: $isShowingActionsMenu,
                    dismissOtherMenu: { isShowingFilterMenu = false },
                    frame: $actionsButtonFrame
                )

                Button(action: onTogglePin) {
                    HeaderIconLabel(systemName: isPinned ? "pin.fill" : "pin", isActive: isPinned, activeIconColor: .historyPrimary)
                }
                .buttonStyle(HeaderIconButtonStyle())
                .background(ScreenFrameReader(frame: $pinButtonFrame))
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isShowingPinHint = false
                    }
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isShowingPinHint = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func dropdownButton(
        systemName: String,
        helpText: String,
        isActive: Bool,
        activeIconColor: Color = .primary,
        isPresented: Binding<Bool>,
        dismissOtherMenu: @escaping () -> Void,
        frame: Binding<CGRect>
    ) -> some View {
        Button {
            dismissOtherMenu()
            isPresented.wrappedValue.toggle()
        } label: {
            HeaderIconLabel(systemName: systemName, isActive: isActive, activeIconColor: activeIconColor)
        }
        .buttonStyle(HeaderIconButtonStyle())
        .help(helpText)
        .background(ScreenFrameReader(frame: frame))
    }
}

struct ClipboardHistoryFooterView: View {
    let itemCountText: String
    let localizer: Localizer
    @Binding var isShowingShortcutHints: Bool
    @Binding var shortcutButtonFrame: CGRect

    var body: some View {
        HStack {
            Text(itemCountText)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: {}) {
                HStack(spacing: 6) {
                    Text(localizer.historyShortcutHintsButton)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .background(ScreenFrameReader(frame: $shortcutButtonFrame))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isShowingShortcutHints = hovering
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct ClipboardHistoryShortcutHintsView: View {
    private let keyCapsuleWidth: CGFloat = 28

    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shortcutRow(key: "⏎", title: localizer.historyShortcutPaste)
            shortcutRow(key: "⌘P", title: localizer.historyShortcutPin)
            shortcutRow(key: "⌘⌫", title: localizer.historyShortcutDelete)
            shortcutRow(key: "⌘⌥P", title: localizer.historyShortcutWindowPin)
        }
        .padding(8)
        .frame(width: 228, alignment: .leading)
    }

    private func shortcutRow(key: String, title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            keyCapsules(for: key)
        }
    }

    private func keyCapsules(for key: String) -> some View {
        HStack(spacing: 6) {
            ForEach(splitShortcut(key), id: \.self) { segment in
                Text(segment)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.historyPrimary)
                    .frame(width: keyCapsuleWidth)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.historyPrimary.opacity(0.12))
                    )
            }
        }
        .frame(alignment: .trailing)
    }

    private func splitShortcut(_ shortcut: String) -> [String] {
        var segments: [String] = []

        for character in shortcut {
            let token = String(character)
            if token == " " { continue }
            segments.append(token)
        }

        return segments
    }
}

struct ClipboardHistoryPinHintView: View {
    private let keyCapsuleWidth: CGFloat = 28

    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(localizer.historyShortcutWindowPin)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(["⌘", "⌥", "P"], id: \.self) { segment in
                        Text(segment)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.historyPrimary)
                            .frame(width: keyCapsuleWidth)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.historyPrimary.opacity(0.12))
                            )
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 228, alignment: .leading)
    }
}

struct ClipboardHistoryFilterMenuView: View {
    @Binding var filter: ClipboardHistoryContentFilter

    let localizer: Localizer
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            menuButton(title: localizer.historyFilterAll, isSelected: filter == .all) {
                filter = .all
                onDismiss()
            }
            menuButton(title: localizer.historyFilterText, isSelected: filter == .text) {
                filter = .text
                onDismiss()
            }
            menuButton(title: localizer.historyFilterImage, isSelected: filter == .image) {
                filter = .image
                onDismiss()
            }
            menuButton(title: localizer.historyFilterLink, isSelected: filter == .link) {
                filter = .link
                onDismiss()
            }
            menuButton(title: localizer.historyFilterColor, isSelected: filter == .color) {
                filter = .color
                onDismiss()
            }
            menuButton(title: localizer.historyFilterFile, isSelected: filter == .file) {
                filter = .file
                onDismiss()
            }
            menuButton(title: localizer.historyFilterFolder, isSelected: filter == .folder) {
                filter = .folder
                onDismiss()
            }
        }
        .padding(6)
        .frame(width: 120)
    }

    private func menuButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        ClipboardHistoryMenuButton(title: title, isSelected: isSelected, action: action)
    }
}

struct ClipboardHistoryActionsMenuView: View {
    let localizer: Localizer
    let isCapturePaused: Bool
    let historySortOrder: HistorySortOrder
    let onToggleCapture: () -> Void
    let onSelectSortOrder: (HistorySortOrder) -> Void
    let onClearHistory: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            menuButton(title: isCapturePaused ? localizer.historyResumeCapture : localizer.historyPauseCapture) {
                onToggleCapture()
            }

            Divider()
                .overlay(Color.black.opacity(0.08))

            Text(localizer.historySortSection)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            menuButton(title: localizer.historySortDescending, isSelected: historySortOrder == .descending) {
                onSelectSortOrder(.descending)
            }

            menuButton(title: localizer.historySortAscending, isSelected: historySortOrder == .ascending) {
                onSelectSortOrder(.ascending)
            }

            Divider()
                .overlay(Color.black.opacity(0.08))

            menuButton(title: localizer.historyClearAll) {
                onClearHistory()
            }

            Divider()
                .overlay(Color.black.opacity(0.08))

            menuButton(title: localizer.historyMoreSettings) {
                onOpenSettings()
            }
        }
        .padding(6)
        .frame(width: 156)
    }

    private func menuButton(title: String, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
        ClipboardHistoryMenuButton(title: title, isSelected: isSelected, action: action)
    }
}

private struct ClipboardHistoryMenuButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "circle.fill")
                    .font(.system(size: isSelected ? 11 : 5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.historyPrimary : Color.clear)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PopoverMenuButtonStyle())
    }
}
