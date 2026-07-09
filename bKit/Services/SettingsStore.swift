//
//  SettingsStore.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private var isRevertingLaunchAtLoginFailure = false

    // 应用内语言，默认中文。
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    // 是否在登录后自动启动应用。
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard !isRevertingLaunchAtLoginFailure else { return }
            guard launchAtLoginEnabled != oldValue else { return }

            let didUpdate = LaunchAtLoginManager.setEnabled(launchAtLoginEnabled)
            guard !didUpdate else { return }

            isRevertingLaunchAtLoginFailure = true
            launchAtLoginEnabled = oldValue
            isRevertingLaunchAtLoginFailure = false
        }
    }

    // 历史保留天数，默认 30 天。
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays)
        }
    }

    // 历史窗口最多显示多少条记录；0 表示不限制。
    @Published var historyVisibleItemLimit: Int {
        didSet {
            UserDefaults.standard.set(historyVisibleItemLimit, forKey: Keys.historyVisibleItemLimit)
        }
    }

    // 本地存储上限，单位 MB。
    // 剪贴板历史超过这个上限时，会从最旧的内容开始清理。
    @Published var maxStorageMB: Int {
        didSet {
            UserDefaults.standard.set(maxStorageMB, forKey: Keys.maxStorageMB)
        }
    }

    // 是否暂停继续记录新的剪贴板内容。
    @Published var isCapturePaused: Bool {
        didSet {
            UserDefaults.standard.set(isCapturePaused, forKey: Keys.isCapturePaused)
        }
    }

    // 历史列表排序方式，默认按时间倒序。
    @Published var historySortOrder: HistorySortOrder {
        didSet {
            UserDefaults.standard.set(historySortOrder.rawValue, forKey: Keys.historySortOrder)
        }
    }

    // 历史窗口当前使用的内容筛选，关闭窗口后继续保留。
    @Published var historyContentFilter: ClipboardHistoryContentFilter {
        didSet {
            UserDefaults.standard.set(historyContentFilter.rawValue, forKey: Keys.historyContentFilter)
        }
    }

    // 文本、链接、颜色类历史项在主列表里的字号。
    @Published var historyTextFontSize: Int {
        didSet {
            UserDefaults.standard.set(historyTextFontSize, forKey: Keys.historyTextFontSize)
        }
    }

    // 图片类历史项在主列表里的预览高度。
    @Published var historyImagePreviewHeight: Int {
        didSet {
            UserDefaults.standard.set(historyImagePreviewHeight, forKey: Keys.historyImagePreviewHeight)
        }
    }

    // 用户可配置的全局快捷键。
    @Published var shortcut: KeyboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(shortcut.keyCode), forKey: Keys.shortcutKeyCode)
            UserDefaults.standard.set(Int(shortcut.modifiers.intersection([.command, .shift, .option, .control]).rawValue), forKey: Keys.shortcutModifiers)
        }
    }

    init() {
        let defaults = UserDefaults.standard

        // 启动时从 UserDefaults 读取设置。
        // 如果没有历史值，就使用默认值。
        let hasInitializedLaunchAtLogin = defaults.bool(forKey: Keys.hasInitializedLaunchAtLogin)
        let languageRaw = defaults.string(forKey: Keys.language)
        let retention = defaults.object(forKey: Keys.retentionDays) as? Int ?? 30
        let historyVisibleItemLimit = defaults.object(forKey: Keys.historyVisibleItemLimit) as? Int ?? 150
        let storage = defaults.object(forKey: Keys.maxStorageMB) as? Int ?? 200
        let isCapturePaused = defaults.bool(forKey: Keys.isCapturePaused)
        let historySortOrderRaw = defaults.string(forKey: Keys.historySortOrder)
        let historyContentFilterRaw = defaults.string(forKey: Keys.historyContentFilter)
        let historyTextFontSize = defaults.object(forKey: Keys.historyTextFontSize) as? Int ?? 14
        let historyImagePreviewHeight = defaults.object(forKey: Keys.historyImagePreviewHeight) as? Int ?? 100
        let keyCode = defaults.object(forKey: Keys.shortcutKeyCode) as? Int
        let modifiersRaw = defaults.object(forKey: Keys.shortcutModifiers) as? Int

        language = AppLanguage(rawValue: languageRaw ?? "") ?? .zhHans
        let launchAtLoginEnabled = {
            if hasInitializedLaunchAtLogin {
                return LaunchAtLoginManager.isEnabled
            }

            let didEnable = LaunchAtLoginManager.setEnabled(true)
            defaults.set(true, forKey: Keys.hasInitializedLaunchAtLogin)
            return didEnable ? true : LaunchAtLoginManager.isEnabled
        }()
        self.launchAtLoginEnabled = launchAtLoginEnabled
        retentionDays = retention.clamped(to: 1...365)
        self.historyVisibleItemLimit = historyVisibleItemLimit.clamped(to: 0...1000)
        maxStorageMB = storage.clamped(to: 50...1024)
        self.isCapturePaused = isCapturePaused
        historySortOrder = HistorySortOrder(rawValue: historySortOrderRaw ?? "") ?? .descending
        historyContentFilter = ClipboardHistoryContentFilter(rawValue: historyContentFilterRaw ?? "") ?? .all
        self.historyTextFontSize = historyTextFontSize.clamped(to: 12...24)
        self.historyImagePreviewHeight = historyImagePreviewHeight.clamped(to: 100...220)
        shortcut = {
            guard let keyCode, let modifiersRaw else {
                return .default
            }

            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
                .intersection([.command, .shift, .option, .control])

            guard !modifiers.isEmpty else {
                return .default
            }

            return KeyboardShortcut(
                keyCode: UInt32(keyCode),
                modifiers: modifiers
            )
        }()
    }

    private enum Keys {
        static let language = "settings.language"
        static let hasInitializedLaunchAtLogin = "settings.hasInitializedLaunchAtLogin"
        static let retentionDays = "settings.retentionDays"
        static let historyVisibleItemLimit = "settings.historyVisibleItemLimit"
        static let maxStorageMB = "settings.maxStorageMB"
        static let isCapturePaused = "settings.isCapturePaused"
        static let historySortOrder = "settings.historySortOrder"
        static let historyContentFilter = "settings.historyContentFilter"
        static let historyTextFontSize = "settings.historyTextFontSize"
        static let historyImagePreviewHeight = "settings.historyImagePreviewHeight"
        static let shortcutKeyCode = "settings.shortcut.keyCode"
        static let shortcutModifiers = "settings.shortcut.modifiers"
    }
}

enum HistorySortOrder: String, CaseIterable, Identifiable {
    case descending
    case ascending

    var id: String { rawValue }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // 防止设置页把值写到约束区间外面。
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
