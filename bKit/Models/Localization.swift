//
//  Localization.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import Foundation

// 先做应用内语言切换，不跟随系统语言。
// 这样用户在设置页切换后，界面可以立即刷新。
enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans:
            return "中文"
        case .en:
            return "English"
        }
    }
}

// 所有可见文案都统一集中在这里。
// 后续继续扩功能时，只需要补这里的中英文，不要把新字符串直接写死在 View 里。
struct Localizer {
    let language: AppLanguage

    var appName: String { text(zh: "bKit", en: "bKit") }
    var menuOpenHistory: String { text(zh: "打开剪贴板历史", en: "Open Clipboard History") }
    var menuSettings: String { text(zh: "设置...", en: "Settings...") }
    var menuQuit: String { text(zh: "退出 bKit", en: "Quit bKit") }
    var filterAll: String { text(zh: "全部", en: "All") }
    var filterClipboard: String { text(zh: "剪贴板", en: "Clipboard") }

    var settingsTitle: String { text(zh: "设置", en: "Settings") }
    var settingsSectionLanguage: String { text(zh: "语言", en: "Language") }
    var settingsSectionShortcut: String { text(zh: "快捷键", en: "Shortcut") }
    var settingsSectionGeneral: String { text(zh: "通用", en: "General") }
    var settingsSectionCleanup: String { text(zh: "清理", en: "Cleanup") }
    var settingsSectionDisplay: String { text(zh: "显示", en: "Display") }
    var settingsSectionHistory: String { text(zh: "历史", en: "History") }
    var settingsLanguageLabel: String { text(zh: "界面语言", en: "App language") }
    var settingsLaunchAtLoginLabel: String { text(zh: "开机自动启动", en: "Launch at login") }
    var settingsOpenHistoryLabel: String { text(zh: "打开历史面板", en: "Open history") }
    var settingsShortcutHint: String {
        text(
            zh: "默认快捷键是 Command + Shift + C。点击按钮后按下新的组合键即可修改。",
            en: "Default is Command + Shift + C. Click the button and press a new shortcut to update it."
        )
    }
    var settingsRetainHistoryLabel: String { text(zh: "本地历史保留时长", en: "Retain local history") }
    var settingsVisibleHistoryLimitLabel: String { text(zh: "窗口显示记录条数", en: "Visible history items") }
    var settingsStorageLimitLabel: String { text(zh: "存储上限", en: "Storage limit") }
    var settingsHistoryTextFontSizeLabel: String { text(zh: "文本字号", en: "Text font size") }
    var settingsHistoryImageHeightLabel: String { text(zh: "图片预览高度", en: "Image preview height") }
    var settingsCleanupHint: String {
        text(
            zh: "超过保留时间的内容，或超出存储上限的旧内容，会被自动删除。",
            en: "Items older than the retention window or beyond the storage limit are removed automatically."
        )
    }
    var settingsUnlimitedOption: String { text(zh: "不限制", en: "Unlimited") }
    var settingsClearHistoryButton: String { text(zh: "清空剪贴板历史", en: "Clear clipboard history") }
    var shortcutRecording: String { text(zh: "请按快捷键...", en: "Press shortcut...") }

    var historySearchPlaceholder: String { text(zh: "搜索剪贴板历史", en: "Search clipboard history") }
    var historyFilterAll: String { text(zh: "全部", en: "All") }
    var historyFilterText: String { text(zh: "文本", en: "Text") }
    var historyFilterImage: String { text(zh: "图片", en: "Image") }
    var historyFilterLink: String { text(zh: "链接", en: "Link") }
    var historyFilterColor: String { text(zh: "颜色", en: "Color") }
    var historyFilterFile: String { text(zh: "文件", en: "File") }
    var historyFilterFolder: String { text(zh: "文件夹", en: "Folder") }
    var historyFilterButton: String { text(zh: "过滤", en: "Filter") }
    var historyActionsButton: String { text(zh: "更多操作", en: "More actions") }
    var historyPauseCapture: String { text(zh: "暂停记录", en: "Pause recording") }
    var historyResumeCapture: String { text(zh: "继续记录", en: "Resume recording") }
    var historySortSection: String { text(zh: "顺序", en: "Order") }
    var historySortDescending: String { text(zh: "倒序", en: "Newest first") }
    var historySortAscending: String { text(zh: "正序", en: "Oldest first") }
    var historyClearAll: String { text(zh: "清空剪贴板", en: "Clear clipboard history") }
    var historyMoreSettings: String { text(zh: "更多设置", en: "More settings") }
    var historyEmptyTitle: String { text(zh: "暂无剪贴板历史", en: "No Clipboard History") }
    var historyEmptyDescription: String {
        text(zh: "先复制一段文字或一张图片，这里就会开始积累历史。", en: "Copy some text or an image to start building history.")
    }
    var historyNoResultDescription: String {
        text(zh: "没有找到匹配的内容。", en: "No result matched your search.")
    }
    var historySettingsButton: String { text(zh: "设置", en: "Settings") }
    var historyCloseButton: String { text(zh: "关闭", en: "Close") }
    var historyPinButton: String { text(zh: "固定窗口", en: "Pin window") }
    var historyUnpinButton: String { text(zh: "取消固定", en: "Unpin window") }
    var historyPausedBadge: String { text(zh: "已暂停记录", en: "Recording paused") }
    var historyFooterPasteBack: String { text(zh: "按回车粘贴到当前输入框", en: "Press Return to paste into the current field") }
    var historyShortcutHintsButton: String { text(zh: "快捷键", en: "Shortcuts") }
    var historyShortcutPaste: String { text(zh: "粘贴选中项", en: "Paste selected item") }
    var historyShortcutPin: String { text(zh: "置顶或取消置顶", en: "Pin or unpin item") }
    var historyShortcutDelete: String { text(zh: "删除选中项", en: "Delete selected item") }
    var historyShortcutWindowPin: String { text(zh: "切换窗口置顶", en: "Toggle window pinning") }
    var historyUnknownSource: String { text(zh: "未知来源", en: "Unknown") }
    var historyDeleteItemConfirmTitle: String { text(zh: "确认删除这条历史？", en: "Delete this history item?") }
    var historyDeleteItemConfirmMessage: String { text(zh: "删除后将无法恢复这条文本或图片历史。", en: "This text or image history item cannot be recovered after deletion.") }
    var historyDeleteItemConfirmAction: String { text(zh: "确认删除", en: "Delete item") }
    var historyOpenTooManyFilesTitle: String { text(zh: "暂不支持一次打开超过 5 个文件", en: "Opening more than 5 files is not supported yet") }
    var historyOpenTooManyFilesMessage: String {
        text(
            zh: "为避免一次打开过多访达窗口，当前最多支持处理 5 个文件或文件夹。请缩小选择范围后再试。",
            en: "To avoid opening too many Finder windows at once, bPaste currently supports up to 5 files or folders at a time."
        )
    }
    var historyPreviewLastCopied: String { text(zh: "上次复制时间", en: "Last copied") }
    var historyPreviewCharacters: String { text(zh: "字符数", en: "Characters") }
    var historyPreviewDimensions: String { text(zh: "图片尺寸", en: "Image size") }
    var historyPreviewFileCount: String { text(zh: "文件数量", en: "File count") }
    var historyPreviewImageSize: String { text(zh: "图片大小", en: "Image file size") }
    var historyPreviewStorageSize: String { text(zh: "内容大小", en: "Storage size") }
    var historyPreviewContentType: String { text(zh: "内容类别", en: "Content type") }
    var historyPreviewTypeText: String { text(zh: "文本", en: "Text") }
    var historyPreviewTypeLink: String { text(zh: "链接", en: "Link") }
    var historyPreviewTypeColor: String { text(zh: "颜色", en: "Color") }
    var historyPreviewTypeImage: String { text(zh: "图片", en: "Image") }
    var historyPreviewTypeFile: String { text(zh: "文件", en: "File") }
    var historyFileFolderLabel: String { text(zh: "文件夹", en: "Folder") }
    var historyFileItemsLabel: String { text(zh: "项", en: "items") }
    var clearHistoryConfirmTitle: String { text(zh: "确认清空剪贴板历史？", en: "Clear clipboard history?") }
    var clearHistoryConfirmMessage: String { text(zh: "这个操作会删除所有已保存的文本和图片历史，且无法恢复。", en: "This deletes all saved text and image history and cannot be undone.") }
    var clearHistoryConfirmAction: String { text(zh: "确认清空", en: "Clear history") }
    var cancelAction: String { text(zh: "取消", en: "Cancel") }

    func dayText(_ value: Int) -> String {
        switch language {
        case .zhHans:
            return "\(value) 天"
        case .en:
            return "\(value) day\(value > 1 ? "s" : "")"
        }
    }

    func hourText(_ value: Int) -> String {
        switch language {
        case .zhHans:
            return "\(value) 小时"
        case .en:
            return "\(value) hour\(value > 1 ? "s" : "")"
        }
    }

    func storageText(_ value: Int) -> String {
        "\(value) MB"
    }

    func historyLimitText(_ value: Int) -> String {
        guard value > 0 else { return settingsUnlimitedOption }

        switch language {
        case .zhHans:
            return "\(value) 条"
        case .en:
            return "\(value) items"
        }
    }

    func pixelText(_ value: Int) -> String {
        switch language {
        case .zhHans:
            return "\(value) px"
        case .en:
            return "\(value) px"
        }
    }

    func itemCountText(_ value: Int) -> String {
        switch language {
        case .zhHans:
            return "\(value) 条"
        case .en:
            return "\(value) items"
        }
    }

    private func text(zh: String, en: String) -> String {
        switch language {
        case .zhHans:
            return zh
        case .en:
            return en
        }
    }
}
