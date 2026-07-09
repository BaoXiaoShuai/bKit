//
//  CodexQuotaAnalyzer.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// 基础数据类型
import Foundation

enum CodexQuotaAnalyzer {
    private static let criticalRemainingPercent = 5.0
    private static let paceDeltaThreshold = 15.0

    static func analyze(snapshot: QuotaSnapshot?, now: Date = Date()) -> QuotaPace {
        guard let snapshot else {
            return QuotaPace(fiveHour: nil, weekly: nil, summary: .unknown)
        }

        let fiveHour = analyze(window: snapshot.fiveHourWindow, now: now)
        let weekly = analyze(window: snapshot.weeklyWindow, now: now)
        return QuotaPace(
            fiveHour: fiveHour,
            weekly: weekly,
            summary: summarize(fiveHour: fiveHour, weekly: weekly)
        )
    }

    private static func analyze(window: QuotaWindow?, now: Date) -> QuotaWindowPace? {
        guard let window else {
            return nil
        }

        var idealRemainingPercent: Double?
        var paceDelta: Double?
        var status: PaceStatus = .unknown

        if let duration = window.windowDurationMins,
           let resetsAt = window.resetsAt,
           duration > 0 {
            let remainingSeconds = max(0, resetsAt.timeIntervalSince(now))
            let ideal = max(0, min(100, remainingSeconds / (duration * 60) * 100))
            idealRemainingPercent = round1(ideal)
            paceDelta = round1(window.remainingPercent - ideal)

            if window.remainingPercent <= criticalRemainingPercent {
                status = .critical
            } else if let paceDelta, paceDelta >= paceDeltaThreshold {
                status = .accelerate
            } else if let paceDelta, paceDelta <= -paceDeltaThreshold {
                status = .slow
            } else {
                status = .normal
            }
        } else if window.remainingPercent <= criticalRemainingPercent {
            status = .critical
        }

        return QuotaWindowPace(
            remainingPercent: window.remainingPercent,
            idealRemainingPercent: idealRemainingPercent,
            paceDelta: paceDelta,
            status: status
        )
    }

    private static func summarize(fiveHour: QuotaWindowPace?, weekly: QuotaWindowPace?) -> PaceStatus {
        if fiveHour?.status == .critical || weekly?.status == .critical {
            return .critical
        }
        if weekly?.status == .slow {
            return fiveHour?.status == .slow ? .slow : .recentFast
        }
        if fiveHour?.status == .slow {
            return .recentFast
        }
        if weekly?.status == .accelerate && fiveHour?.status != .slow {
            return .accelerate
        }
        if weekly?.status == .normal || fiveHour?.status == .normal {
            return .normal
        }
        return weekly?.status ?? fiveHour?.status ?? .unknown
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
