//
//  ClipboardHistoryView.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    let isHoverPreviewEnabled = true
    let isFileRevealShortcutEnabled = false

    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: SettingsStore

    let close: () -> Void
    let isPinned: Bool
    let togglePin: () -> Void
    let restoreAndPaste: (ClipboardItem) -> Void
    let openSettings: () -> Void
    let clearHistory: () -> Void
    let setModalPresentation: (Bool) -> Void

    @State var query = ""
    @State var selection: ClipboardItem.ID?
    @State var eventMonitor: Any?
    @State var contentFilter: ClipboardHistoryContentFilter = .all
    @State var isConfirmingClearHistory = false
    @State var isConfirmingDeleteHistoryItem = false
    @State var isShowingFileOpenLimitAlert = false
    @State var pendingDeleteItemID: ClipboardItem.ID?
    @State var isShowingFilterMenu = false
    @State var isShowingActionsMenu = false
    @State var isShowingShortcutHints = false
    @State var isShowingPinHint = false
    @State var filterButtonFrame: CGRect = .zero
    @State var actionsButtonFrame: CGRect = .zero
    @State var shortcutButtonFrame: CGRect = .zero
    @State var pinButtonFrame: CGRect = .zero
    @State var dropdownController = DropdownPanelController()
    @State var hoverPreviewController = HoverPreviewPanelController()
    @State var hoverPreviewTask: DispatchWorkItem?
    @State var hoverPreviewDismissTask: DispatchWorkItem?
    @State var hoverPreviewItemID: ClipboardItem.ID?
    @State var hoveredRowItemID: ClipboardItem.ID?
    @State var hoveredRowFrame: CGRect = .zero
    @State var isHoveringPreview = false
    @State var isShowingHoverPreview = false
    @FocusState var isSearchFocused: Bool

    var visibleItems: [ClipboardItem] {
        // 搜索结果始终基于当前历史列表实时过滤。
        let filtered = store.filteredItems(query: query).filter { item in
            switch contentFilter {
            case .all:
                return true
            case .text:
                return item.kind == .text
            case .image:
                return item.kind == .image
            case .link:
                return item.kind == .text && item.detectedTextContentType == .link
            case .color:
                return item.kind == .text && item.detectedTextContentType == .color
            case .file:
                return item.kind == .file && item.containsFileReference
            case .folder:
                return item.kind == .file && item.containsOnlyFolderReferences
            }
        }

        switch settings.historySortOrder {
        case .descending:
            return limitedItems(from: orderedItems(filtered))
        case .ascending:
            return limitedItems(from: orderedItems(filtered.reversed()))
        }
    }

    var localizer: Localizer {
        Localizer(language: settings.language)
    }

    func limitedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        guard settings.historyVisibleItemLimit > 0 else { return items }
        return Array(items.prefix(settings.historyVisibleItemLimit))
    }

    var body: some View {
        baseView
    }

    var baseView: some View {
        sizedContent
            .onAppear(perform: handleAppear)
            .onSubmit(handleSubmit)
            .onDisappear(perform: handleDisappear)
            .onChange(of: contentFilter) { _, filter in
                settings.historyContentFilter = filter
            }
    }

    var sizedContent: some View {
        content
            .frame(minWidth: 400, minHeight: 480)
            .background(GlassBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(windowOutline)
            .modifier(
                ClipboardHistoryStateObservers(
                    query: $query,
                    selection: $selection,
                    contentFilter: $contentFilter,
                    isShowingHoverPreview: $isShowingHoverPreview,
                    isConfirmingClearHistory: $isConfirmingClearHistory,
                    isConfirmingDeleteHistoryItem: $isConfirmingDeleteHistoryItem,
                    isShowingFilterMenu: $isShowingFilterMenu,
                    isShowingActionsMenu: $isShowingActionsMenu,
                    isShowingShortcutHints: $isShowingShortcutHints,
                    isShowingPinHint: $isShowingPinHint,
                    filterButtonFrame: $filterButtonFrame,
                    actionsButtonFrame: $actionsButtonFrame,
                    shortcutButtonFrame: $shortcutButtonFrame,
                    pinButtonFrame: $pinButtonFrame,
                    visibleItemIDs: visibleItems.map(\.id),
                    syncModalPresentation: syncModalPresentation,
                    updateDropdownPresentation: updateDropdownPresentation
                )
            )
            .alert(localizer.clearHistoryConfirmTitle, isPresented: $isConfirmingClearHistory, actions: clearHistoryAlertActions, message: clearHistoryAlertMessage)
            .alert(localizer.historyDeleteItemConfirmTitle, isPresented: $isConfirmingDeleteHistoryItem, actions: deleteHistoryAlertActions, message: deleteHistoryAlertMessage)
            .alert(localizer.historyOpenTooManyFilesTitle, isPresented: $isShowingFileOpenLimitAlert) {
                Button(localizer.cancelAction, role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text(localizer.historyOpenTooManyFilesMessage)
            }
    }

    var content: some View {
        VStack(spacing: 0) {
            headerSection
            listSection
            footerSection
        }
    }

    var headerSection: some View {
        ClipboardHistoryHeaderView(
            query: $query,
            isShowingFilterMenu: $isShowingFilterMenu,
            isShowingActionsMenu: $isShowingActionsMenu,
            isShowingPinHint: $isShowingPinHint,
            filterButtonFrame: $filterButtonFrame,
            actionsButtonFrame: $actionsButtonFrame,
            pinButtonFrame: $pinButtonFrame,
            localizer: localizer,
            isCapturePaused: settings.isCapturePaused,
            isPinned: isPinned,
            filter: contentFilter,
            searchFocus: $isSearchFocused,
            onTogglePin: togglePin
        )
        .background(panelCard)
    }

    @ViewBuilder
    var listSection: some View {
        if visibleItems.isEmpty {
            ContentUnavailableView(
                localizer.historyEmptyTitle,
                systemImage: "doc.on.clipboard",
                description: Text(query.isEmpty ? localizer.historyEmptyDescription : localizer.historyNoResultDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelCard)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            ClipboardRowView(
                                item: item,
                                imageURL: store.imageURL(for: item),
                                fileURLs: store.fileURLs(for: item),
                                sourceIcon: store.sourceIcon(for: item),
                                isSelected: selection == item.id,
                                localizer: localizer,
                                textFontSize: CGFloat(settings.historyTextFontSize),
                                imagePreviewHeight: CGFloat(settings.historyImagePreviewHeight),
                                onHoverChanged: { isHovering, frame in
                                    handleRowHover(isHovering: isHovering, item: item, imageURL: store.imageURL(for: item), frame: frame)
                                }
                            )
                            .id(item.id)
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                            .onTapGesture(count: 2) {
                                restore(item)
                            }
                            .onTapGesture {
                                handleItemTap(item)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .background(panelCard)
                .onChange(of: selection) { _, selection in
                    guard let selection else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }
        }
    }

    var footerSection: some View {
        ClipboardHistoryFooterView(
            itemCountText: localizer.itemCountText(visibleItems.count),
            localizer: localizer,
            isShowingShortcutHints: $isShowingShortcutHints,
            shortcutButtonFrame: $shortcutButtonFrame
        )
        .background(panelCard)
    }

    var windowOutline: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
    }
}
