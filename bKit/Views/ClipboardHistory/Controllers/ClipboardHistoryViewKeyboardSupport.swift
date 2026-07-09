//
//  ClipboardHistoryViewKeyboardSupport.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import SwiftUI

// 这层放历史窗口的键盘和状态同步逻辑：
// 1. 键盘导航与快捷键
// 2. 列表选中项同步
// 3. 弹层位置刷新
// 这些逻辑和页面结构解耦后，主文件会更容易继续扩展。

extension ClipboardHistoryView {
    func installKeyboardMonitor() {
        removeKeyboardMonitor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isBlockingPanelShortcuts {
                return event
            }

            if handleCommandShortcut(for: event) {
                return nil
            }

            // 普通文字输入必须继续交给搜索框，否则用户会感觉“输入框点了也不能打字”。
            // 这里仅拦截面板级快捷键，把普通字符、删除、输入法组合键都放回系统处理。
            if shouldAllowTextInput(for: event) {
                return event
            }

            switch event.keyCode {
            case 125:
                moveSelection(offset: 1)
                return nil
            case 126:
                moveSelection(offset: -1)
                return nil
            case 36:
                guard let selected = selectedItem else { return nil }
                restore(selected)
                return nil
            case 53:
                close()
                return nil
            default:
                return event
            }
        }
    }

    func shouldAllowTextInput(for event: NSEvent) -> Bool {
        // 输入法候选、组合键和系统编辑命令都不应该被列表导航拦截。
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            return true
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) {
            return true
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control) {
            return true
        }

        // 只有上下箭头、回车、Esc 这几个键需要交给历史列表处理，其余按键都放行。
        let handledKeyCodes: Set<UInt16> = [36, 53, 125, 126]
        return !handledKeyCodes.contains(event.keyCode)
    }

    func handleCommandShortcut(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command else { return false }

        switch event.keyCode {
        case 35:
            togglePinnedSelection()
            return true
        case 51:
            confirmDeleteSelection()
            return true
        default:
            return false
        }
    }

    var isBlockingPanelShortcuts: Bool {
        isConfirmingClearHistory || isConfirmingDeleteHistoryItem || isShowingFileOpenLimitAlert || isShowingFilterMenu || isShowingActionsMenu
    }

    func removeKeyboardMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    var selectedItem: ClipboardItem? {
        visibleItems.first(where: { $0.id == selection }) ?? visibleItems.first
    }

    func orderedItems<S: Sequence>(_ items: S) -> [ClipboardItem] where S.Element == ClipboardItem {
        let array = Array(items)
        let pinned = array.filter(\.isPinned)
        let regular = array.filter { !$0.isPinned }
        return pinned + regular
    }

    func togglePinnedSelection() {
        guard let selectedItem else { return }
        store.togglePinned(id: selectedItem.id)
    }

    func confirmDeleteSelection() {
        guard let selectedItem else { return }
        pendingDeleteItemID = selectedItem.id
        isConfirmingDeleteHistoryItem = true
    }

    func moveSelection(offset: Int) {
        guard !visibleItems.isEmpty else { return }

        guard let currentSelection = selection,
              let currentIndex = visibleItems.firstIndex(where: { $0.id == currentSelection })
        else {
            selection = visibleItems.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)
        selection = visibleItems[nextIndex].id
    }
}

// 这个修饰器只负责承接历史窗口那串状态监听：
// 1. 同步列表选中项
// 2. 同步弹层展示与重定位
// 3. 避免主视图 body 链过长导致 Swift 编译器超时
struct ClipboardHistoryStateObservers: ViewModifier {
    @Binding var query: String
    @Binding var selection: ClipboardItem.ID?
    @Binding var contentFilter: ClipboardHistoryContentFilter
    @Binding var isShowingHoverPreview: Bool
    @Binding var isConfirmingClearHistory: Bool
    @Binding var isConfirmingDeleteHistoryItem: Bool
    @Binding var isShowingFilterMenu: Bool
    @Binding var isShowingActionsMenu: Bool
    @Binding var isShowingShortcutHints: Bool
    @Binding var isShowingPinHint: Bool
    @Binding var filterButtonFrame: CGRect
    @Binding var actionsButtonFrame: CGRect
    @Binding var shortcutButtonFrame: CGRect
    @Binding var pinButtonFrame: CGRect

    let visibleItemIDs: [ClipboardItem.ID]
    let syncModalPresentation: () -> Void
    let updateDropdownPresentation: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: query) { _, _ in
                // 搜索词改变后，默认把选中项重置到第一条结果。
                selection = visibleItemIDs.first
            }
            .onChange(of: contentFilter) { _, _ in
                selection = visibleItemIDs.first
            }
            .onChange(of: visibleItemIDs) { _, ids in
                if !ids.contains(selection ?? UUID()) {
                    selection = ids.first
                }
            }
            .onChange(of: isShowingHoverPreview) { _, _ in
                syncModalPresentation()
            }
            .onChange(of: isConfirmingClearHistory) { _, _ in
                syncModalPresentation()
            }
            .onChange(of: isConfirmingDeleteHistoryItem) { _, _ in
                syncModalPresentation()
            }
            .onChange(of: isShowingFilterMenu) { _, _ in
                syncModalPresentation()
                updateDropdownPresentation()
            }
            .onChange(of: isShowingActionsMenu) { _, _ in
                syncModalPresentation()
                updateDropdownPresentation()
            }
            .onChange(of: isShowingShortcutHints) { _, _ in
                syncModalPresentation()
                updateDropdownPresentation()
            }
            .onChange(of: isShowingPinHint) { _, _ in
                syncModalPresentation()
                updateDropdownPresentation()
            }
            .onChange(of: filterButtonFrame) { _, _ in
                guard isShowingFilterMenu else { return }
                updateDropdownPresentation()
            }
            .onChange(of: actionsButtonFrame) { _, _ in
                guard isShowingActionsMenu else { return }
                updateDropdownPresentation()
            }
            .onChange(of: shortcutButtonFrame) { _, _ in
                guard isShowingShortcutHints else { return }
                updateDropdownPresentation()
            }
            .onChange(of: pinButtonFrame) { _, _ in
                guard isShowingPinHint else { return }
                updateDropdownPresentation()
            }
    }
}
