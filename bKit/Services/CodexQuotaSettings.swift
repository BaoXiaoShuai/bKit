//
//  CodexQuotaSettings.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 状态能力
import Combine
// 数据持久化基础库
import Foundation

final class CodexQuotaSettings: ObservableObject {
    @Published var showFiveHour: Bool {
        didSet { defaults.set(showFiveHour, forKey: Keys.showFiveHour) }
    }

    @Published var showWeekly: Bool {
        didSet { defaults.set(showWeekly, forKey: Keys.showWeekly) }
    }

    @Published var showSummary: Bool {
        didSet { defaults.set(showSummary, forKey: Keys.showSummary) }
    }

    @Published var showResetTime: Bool {
        didSet { defaults.set(showResetTime, forKey: Keys.showResetTime) }
    }

    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showFiveHour = defaults.object(forKey: Keys.showFiveHour) as? Bool ?? true
        showWeekly = defaults.object(forKey: Keys.showWeekly) as? Bool ?? true
        showSummary = defaults.object(forKey: Keys.showSummary) as? Bool ?? false
        showResetTime = defaults.object(forKey: Keys.showResetTime) as? Bool ?? true
        refreshIntervalMinutes = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Double ?? 3
    }

    private enum Keys {
        static let showFiveHour = "codexQuota.statusBar.showFiveHour"
        static let showWeekly = "codexQuota.statusBar.showWeekly"
        static let showSummary = "codexQuota.statusBar.showSummary"
        static let showResetTime = "codexQuota.statusBar.showResetTime"
        static let refreshIntervalMinutes = "codexQuota.refreshIntervalMinutes"
    }
}
