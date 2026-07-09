//
//  CodexQuotaClient.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// macOS 进程与文件能力
import Foundation

enum CodexQuotaClientError: LocalizedError {
    case codexUnavailable
    case launchFailed(String)
    case timeout(String)
    case invalidResponse
    case missingQuota
    case invalidWindow

    var errorDescription: String? {
        switch self {
        case .codexUnavailable:
            return "未找到 codex 命令，请确认 Codex CLI 已安装并已登录。"
        case .launchFailed(let message):
            return "Codex app-server 启动失败：\(message)"
        case .timeout(let method):
            return "Codex 请求超时：\(method)"
        case .invalidResponse:
            return "Codex 返回了无法解析的数据。"
        case .missingQuota:
            return "Codex 未返回可用的额度窗口。"
        case .invalidWindow:
            return "Codex 额度窗口缺少 usedPercent 或 reset 时间格式异常。"
        }
    }
}

final class CodexQuotaClient {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 12) {
        self.timeoutSeconds = timeoutSeconds
    }

    func fetchQuota(completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.readQuota()
                DispatchQueue.main.async {
                    completion(.success(snapshot))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func readQuota() throws -> QuotaSnapshot {
        guard let codexPath = resolvedCodexPath() else {
            throw CodexQuotaClientError.codexUnavailable
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let collector = RPCResponseCollector()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.append(data: data)
        }

        do {
            try process.run()
        } catch {
            throw CodexQuotaClientError.launchFailed(error.localizedDescription)
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }

        try send(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "bkit-codex-quota",
                    "title": "bKit Codex Quota",
                    "version": "0.1.0"
                ],
                "capabilities": NSNull()
            ],
            to: stdin
        )
        _ = try collector.waitForResponse(id: 1, method: "initialize", timeoutSeconds: timeoutSeconds)

        try send(id: 2, method: "account/rateLimits/read", params: nil, to: stdin)
        let result = try collector.waitForResponse(id: 2, method: "account/rateLimits/read", timeoutSeconds: timeoutSeconds)

        if let errorMessage = result["error"] as? [String: Any],
           let message = errorMessage["message"] as? String {
            throw CodexQuotaClientError.launchFailed(message)
        }

        guard let payload = result["result"] as? [String: Any] else {
            throw CodexQuotaClientError.invalidResponse
        }
        return try normalizeQuotaPayload(payload)
    }

    private func resolvedCodexPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let fixedCandidates = [
            environment["CODEX_CLI_PATH"],
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.npm-global/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        let pathCandidates: [String?] = environment["PATH"]?
            .split(separator: ":")
            .map { "\($0)/codex" } ?? []

        return (fixedCandidates + pathCandidates)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func send(id: Int, method: String, params: [String: Any]?, to pipe: Pipe) throws {
        var payload: [String: Any] = [
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    private func normalizeQuotaPayload(_ payload: [String: Any]) throws -> QuotaSnapshot {
        guard let limits = payload["rateLimitsByLimitId"] as? [String: Any],
              let codex = limits["codex"] as? [String: Any] else {
            throw CodexQuotaClientError.missingQuota
        }

        let primary = try normalizeWindow(codex["primary"])
        let secondary = try normalizeWindow(codex["secondary"])
        guard let activeWindow = primary ?? secondary else {
            throw CodexQuotaClientError.missingQuota
        }

        return QuotaSnapshot(
            limitId: codex["limitId"] as? String ?? "codex",
            limitName: codex["limitName"] as? String ?? "Codex",
            planType: codex["planType"] as? String ?? "unknown",
            reachedType: codex["rateLimitReachedType"] as? String,
            primary: primary,
            secondary: secondary,
            remainingPercent: activeWindow.remainingPercent,
            usedPercent: activeWindow.usedPercent,
            resetsAt: activeWindow.resetsAt,
            fetchedAt: Date()
        )
    }

    private func normalizeWindow(_ value: Any?) throws -> QuotaWindow? {
        guard let window = value as? [String: Any] else {
            return nil
        }
        guard let usedPercent = numberValue(window["usedPercent"]) else {
            throw CodexQuotaClientError.invalidWindow
        }
        let resetSeconds = numberValue(window["resetsAt"])
        let resetDate = resetSeconds.map { Date(timeIntervalSince1970: $0) }
        let remainingPercent = max(0, min(100, 100 - usedPercent))

        return QuotaWindow(
            usedPercent: round1(max(0, min(100, usedPercent))),
            remainingPercent: round1(remainingPercent),
            windowDurationMins: numberValue(window["windowDurationMins"]),
            resetsAt: resetDate
        )
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

final class RPCResponseCollector {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]

    func append(data: Data) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        while let lineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<lineRange.lowerBound)
            buffer.removeSubrange(0...lineRange.lowerBound)

            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = object["id"] as? Int else {
                continue
            }
            responses[id] = object
        }
    }

    func waitForResponse(id: Int, method: String, timeoutSeconds: TimeInterval) throws -> [String: Any] {
        let timeoutDate = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeoutDate {
            lock.lock()
            if let response = responses.removeValue(forKey: id) {
                lock.unlock()
                return response
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw CodexQuotaClientError.timeout(method)
    }
}
