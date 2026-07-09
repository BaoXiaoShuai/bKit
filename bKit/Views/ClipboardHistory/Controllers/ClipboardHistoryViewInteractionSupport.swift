//
//  ClipboardHistoryViewInteractionSupport.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import SwiftUI

// 这层专门承接历史主窗口的交互行为：
// 1. 生命周期和弹窗确认
// 2. 鼠标点击与链接打开
// 3. 悬浮预览和下拉菜单浮层
// 主视图本身只保留页面结构与状态声明。

extension ClipboardHistoryView {
    func handleAppear() {
        contentFilter = settings.historyContentFilter
        selection = visibleItems.first?.id
        installKeyboardMonitor()
        // 历史面板打开后默认把焦点给搜索框，便于直接输入关键字。
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    func handleSubmit() {
        // 在搜索框按回车时，把当前选中项回填到系统剪贴板。
        guard let selected = visibleItems.first(where: { $0.id == selection }) ?? visibleItems.first else { return }
        restore(selected)
    }

    func handleDisappear() {
        setModalPresentation(false)
        hoverPreviewTask?.cancel()
        hoverPreviewDismissTask?.cancel()
        hoverPreviewController.close()
        dropdownController.close()
        removeKeyboardMonitor()
    }

    @ViewBuilder
    func clearHistoryAlertActions() -> some View {
        Button(localizer.cancelAction, role: .cancel) {}
            .keyboardShortcut(.cancelAction)
        Button(localizer.clearHistoryConfirmAction, role: .destructive) {
            clearHistory()
        }
        .keyboardShortcut(.defaultAction)
    }

    func clearHistoryAlertMessage() -> some View {
        Text(localizer.clearHistoryConfirmMessage)
    }

    @ViewBuilder
    func deleteHistoryAlertActions() -> some View {
        Button(localizer.cancelAction, role: .cancel) {
            pendingDeleteItemID = nil
        }
        .keyboardShortcut(.cancelAction)
        Button(localizer.historyDeleteItemConfirmAction, role: .destructive) {
            guard let pendingDeleteItemID else { return }
            store.deleteItem(id: pendingDeleteItemID)
            self.pendingDeleteItemID = nil
        }
        .keyboardShortcut(.defaultAction)
    }

    func deleteHistoryAlertMessage() -> some View {
        Text(localizer.historyDeleteItemConfirmMessage)
    }

    func restore(_ item: ClipboardItem) {
        restoreAndPaste(item)
    }

    func handleItemTap(_ item: ClipboardItem) {
        selection = item.id

        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else { return }

        if item.detectedTextContentType == .link, let url = item.detectedLinkURL {
            NSWorkspace.shared.open(url)
            return
        }

        // 这条能力先保留代码但默认关闭。
        // 原因是沙盒权限下，通过历史里的 bookmark 恢复访达定位并不稳定，
        // 目前会遇到“没有权限打开文件夹”的系统报错，先避免给用户错误反馈。
        guard isFileRevealShortcutEnabled else { return }
        guard item.kind == .file else { return }

        openFileItemInFinder(item)
    }

    func openFileItemInFinder(_ item: ClipboardItem) {
        let urls = store.fileURLs(for: item)
        guard !urls.isEmpty else { return }

        if urls.count > 5 {
            isShowingFileOpenLimitAlert = true
            return
        }

        if urls.count == 1, let url = urls.first {
            openFinderLocation(for: url)
            return
        }

        let parentGroups = Dictionary(grouping: urls) { finderTargetPath(for: $0).path }

        if parentGroups.count == 1 {
            guard let firstPath = parentGroups.keys.first else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: firstPath, isDirectory: true))
            return
        }

        let sortedParents = parentGroups.keys.sorted()
        if sortedParents.count > 5 {
            isShowingFileOpenLimitAlert = true
            return
        }

        for parentPath in sortedParents {
            NSWorkspace.shared.open(URL(fileURLWithPath: parentPath, isDirectory: true))
        }
    }

    func openFinderLocation(for url: URL) {
        let targetURL = finderTargetPath(for: url)
        NSWorkspace.shared.open(targetURL)
    }

    func finderTargetPath(for url: URL) -> URL {
        url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }

    func syncModalPresentation() {
        setModalPresentation(isConfirmingClearHistory || isConfirmingDeleteHistoryItem || isShowingFilterMenu || isShowingActionsMenu || isShowingShortcutHints || isShowingPinHint || isShowingHoverPreview)
    }

    func handleRowHover(isHovering: Bool, item: ClipboardItem, imageURL: URL?, frame: CGRect) {
        guard isHoverPreviewEnabled else {
            hoverPreviewTask?.cancel()
            hoverPreviewDismissTask?.cancel()
            hoverPreviewItemID = nil
            hoveredRowItemID = nil
            hoveredRowFrame = .zero
            isHoveringPreview = false
            isShowingHoverPreview = false
            hoverPreviewController.close()
            return
        }

        if isHovering {
            hoveredRowItemID = item.id
            hoveredRowFrame = frame
            hoverPreviewItemID = item.id
            hoverPreviewDismissTask?.cancel()
            hoverPreviewTask?.cancel()

            // 第一次悬浮保持 3 秒延迟；一旦详情窗已经显示，切到其它条目时立即切换内容。
            if hoverPreviewController.isVisible {
                presentHoverPreview(for: item, imageURL: imageURL, anchorFrame: frame)
                return
            }

            let task = DispatchWorkItem { [hoverPreviewItemID] in
                guard hoverPreviewItemID == item.id else { return }
                Task { @MainActor in
                    presentHoverPreview(for: item, imageURL: imageURL, anchorFrame: hoveredRowFrame == .zero ? frame : hoveredRowFrame)
                }
            }
            hoverPreviewTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
            return
        }

        if hoveredRowItemID == item.id {
            hoveredRowItemID = nil
            hoveredRowFrame = .zero
        }

        if hoverPreviewItemID == item.id {
            hoverPreviewTask?.cancel()
            scheduleHoverPreviewDismissIfNeeded()
        }
    }

    func presentHoverPreview(for item: ClipboardItem, imageURL: URL?, anchorFrame: CGRect) {
        hoverPreviewController.present(
            itemID: item.id,
            content: AnyView(HoverPreviewContentView(item: item, imageURL: imageURL, fileURLs: store.fileURLs(for: item), localizer: localizer)),
            anchorFrame: anchorFrame,
            width: item.kind == .image ? 360 : 388,
            onHoverChanged: handlePreviewHoverChanged
        )
        isShowingHoverPreview = true
    }

    func handlePreviewHoverChanged(_ isHovering: Bool) {
        isHoveringPreview = isHovering

        if isHovering {
            hoverPreviewDismissTask?.cancel()
        } else {
            scheduleHoverPreviewDismissIfNeeded()
        }
    }

    func scheduleHoverPreviewDismissIfNeeded() {
        hoverPreviewDismissTask?.cancel()

        let task = DispatchWorkItem {
            guard hoveredRowItemID == nil, !isHoveringPreview else { return }
            hoverPreviewTask?.cancel()
            hoverPreviewTask = nil
            hoverPreviewItemID = nil
            isShowingHoverPreview = false
            hoverPreviewController.close()
        }

        hoverPreviewDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    func dismissMenus() {
        isShowingFilterMenu = false
        isShowingActionsMenu = false
    }

    func updateDropdownPresentation() {
        if isShowingFilterMenu {
            dropdownController.present(
                content: AnyView(filterMenuPopover),
                anchorFrame: filterButtonFrame,
                width: 112,
                passthroughFrames: [filterButtonFrame]
            ) {
                isShowingFilterMenu = false
            }
            return
        }

        if isShowingActionsMenu {
            dropdownController.present(
                content: AnyView(actionsMenuPopover),
                anchorFrame: actionsButtonFrame,
                width: 156,
                passthroughFrames: [actionsButtonFrame]
            ) {
                isShowingActionsMenu = false
            }
            return
        }

        if isShowingShortcutHints {
            dropdownController.present(
                content: AnyView(ClipboardHistoryShortcutHintsView(localizer: localizer)),
                anchorFrame: shortcutButtonFrame,
                width: 228
            ) {
                isShowingShortcutHints = false
            }
            return
        }

        if isShowingPinHint {
            dropdownController.present(
                content: AnyView(ClipboardHistoryPinHintView(localizer: localizer)),
                anchorFrame: pinButtonFrame,
                width: 228
            ) {
                isShowingPinHint = false
            }
            return
        }

        dropdownController.close()
    }
}

extension ClipboardHistoryView {
    var panelCard: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color.white.opacity(0.22))
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
    }

    var filterMenuPopover: some View {
        ClipboardHistoryFilterMenuView(
            filter: $contentFilter,
            localizer: localizer,
            onDismiss: { isShowingFilterMenu = false }
        )
    }

    var actionsMenuPopover: some View {
        ClipboardHistoryActionsMenuView(
            localizer: localizer,
            isCapturePaused: settings.isCapturePaused,
            historySortOrder: settings.historySortOrder,
            onToggleCapture: {
                settings.isCapturePaused.toggle()
                isShowingActionsMenu = false
            },
            onSelectSortOrder: { order in
                settings.historySortOrder = order
                isShowingActionsMenu = false
            },
            onClearHistory: {
                isShowingActionsMenu = false
                isConfirmingClearHistory = true
            },
            onOpenSettings: {
                isShowingActionsMenu = false
                openSettings()
            }
        )
    }
}
