//
//  CodexQuotaStore.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 状态能力
import Combine
// 数据持久化基础库
import Foundation

final class CodexQuotaStore: ObservableObject {
    @Published private(set) var status: QuotaLoadStatus = .idle
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var pace = QuotaPace(fiveHour: nil, weekly: nil, summary: .unknown)
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isRefreshing = false

    let settings: CodexQuotaSettings

    private let client: CodexQuotaClient
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let cacheURL: URL
    private let historyURL: URL

    private let fiveHourTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private let weeklyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    init(client: CodexQuotaClient = CodexQuotaClient(), settings: CodexQuotaSettings = CodexQuotaSettings()) {
        self.client = client
        self.settings = settings

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("bKit/CodexQuota", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bKit/CodexQuota", isDirectory: true)
        cacheURL = directory.appendingPathComponent("quota-cache.json")
        historyURL = directory.appendingPathComponent("quota-history.json")

        settings.$refreshIntervalMinutes
            .sink { [weak self] _ in
                self?.restartAutoRefresh()
            }
            .store(in: &cancellables)
    }

    func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder.codexQuota.decode(QuotaCachePayload.self, from: data) else {
            return
        }
        snapshot = payload.quota
        lastUpdatedAt = payload.savedAt
        status = .ready
        pace = CodexQuotaAnalyzer.analyze(snapshot: payload.quota)
    }

    func startAutoRefresh() {
        restartAutoRefresh()
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(reason: String = "manual") {
        if isRefreshing {
            return
        }

        isRefreshing = true
        status = snapshot == nil ? .loading : .ready
        client.fetchQuota { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            switch result {
            case let .success(snapshot):
                self.snapshot = snapshot
                self.lastUpdatedAt = snapshot.fetchedAt
                self.status = .ready
                self.pace = CodexQuotaAnalyzer.analyze(snapshot: snapshot)
                self.saveCache(snapshot)
                self.recordHistory(snapshot)
            case let .failure(error):
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    var errorMessage: String? {
        if case let .failed(message) = status {
            return message
        }
        return nil
    }

    var isLoading: Bool {
        status == .loading || isRefreshing
    }

    func formatPercent(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    func lastUpdatedText() -> String {
        guard let lastUpdatedAt else {
            return "最后更新 --:--"
        }
        return "最后更新 \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    func resetText(for window: QuotaWindow?) -> String {
        guard let resetsAt = window?.resetsAt else {
            return "重置时间未知"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return "重置时间 \(formatter.string(from: resetsAt))"
    }

    private func restartAutoRefresh() {
        stopAutoRefresh()
        let minutes = max(1, min(30, settings.refreshIntervalMinutes))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            self?.refresh(reason: "scheduled")
        }
    }

    private func saveCache(_ snapshot: QuotaSnapshot) {
        let payload = QuotaCachePayload(version: 1, savedAt: Date(), quota: snapshot)
        writeJSON(payload, to: cacheURL)
    }

    private func recordHistory(_ snapshot: QuotaSnapshot) {
        var samples: [QuotaSnapshot] = []
        if let data = try? Data(contentsOf: historyURL),
           let payload = try? JSONDecoder.codexQuota.decode(QuotaHistoryPayload.self, from: data) {
            samples = payload.samples
        }

        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        samples = samples.filter { $0.fetchedAt >= cutoff && $0.fetchedAt != snapshot.fetchedAt }
        samples.append(snapshot)
        samples = Array(samples.suffix(4096))

        let payload = QuotaHistoryPayload(version: 1, samples: samples)
        writeJSON(payload, to: historyURL)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder.codexQuota.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}

extension JSONEncoder {
    static var codexQuota: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var codexQuota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
