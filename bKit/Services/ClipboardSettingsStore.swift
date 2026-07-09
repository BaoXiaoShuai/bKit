//
//  ClipboardSettingsStore.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Combine 状态发布能力
import Combine
// Foundation 本地配置能力
import Foundation

@MainActor
final class ClipboardSettingsStore: ObservableObject {
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays)
        }
    }

    @Published var maxStorageMB: Int {
        didSet {
            UserDefaults.standard.set(maxStorageMB, forKey: Keys.maxStorageMB)
        }
    }

    @Published var isCapturePaused: Bool {
        didSet {
            UserDefaults.standard.set(isCapturePaused, forKey: Keys.isCapturePaused)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        retentionDays = (defaults.object(forKey: Keys.retentionDays) as? Int ?? 30).clamped(to: 1...365)
        maxStorageMB = (defaults.object(forKey: Keys.maxStorageMB) as? Int ?? 200).clamped(to: 50...1024)
        isCapturePaused = defaults.bool(forKey: Keys.isCapturePaused)
    }

    private enum Keys {
        static let retentionDays = "clipboard.retentionDays"
        static let maxStorageMB = "clipboard.maxStorageMB"
        static let isCapturePaused = "clipboard.isCapturePaused"
    }
}

private extension Int {
    /// 把数值限制在指定区间，避免异常配置影响清理逻辑。
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
