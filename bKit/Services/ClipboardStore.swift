//
//  ClipboardStore.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    // 这是 UI 读取的最终历史列表，按时间倒序排列。
    @Published private(set) var items: [ClipboardItem] = []

    private let settings: SettingsStore
    // 当用户从历史中“恢复”一项到系统剪贴板时，
    // 我们会临时记住它的 hash，避免被监听器当成新内容再收录一次。
    private var ignoredHashes: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    private let fileManager = FileManager.default
    private let manifestURL: URL
    private let imagesDirectoryURL: URL
    private var hasBootstrapped = false

    init(settings: SettingsStore) {
        self.settings = settings

        // 所有数据都保存在 Application Support/bKit 目录下：
        // history.json 保存元数据，images 目录保存图片文件。
        let rootURL = Self.applicationSupportURL()
        manifestURL = rootURL.appendingPathComponent("history.json")
        imagesDirectoryURL = rootURL.appendingPathComponent("images", isDirectory: true)

        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)

        // 设置改变后，立刻重新清理一次。
        settings.$retentionDays
            .merge(with: settings.$maxStorageMB)
            .sink { [weak self] _ in
                guard let self, self.hasBootstrapped else { return }
                self.performCleanup()
            }
            .store(in: &cancellables)
    }

    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // 把首轮历史加载和清理显式放到启动阶段之外调用，
        // 避免 AppState 初始化时把所有工作都挤在同一帧里。
        load()
        performCleanup()
    }

    func addText(_ text: String, sourceApp: ClipboardSourceApp?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 用内容 hash 做简单去重：
        // 1. 避免连续复制同一条内容
        // 2. 避免手动恢复内容后又被重新收录
        let hash = Self.hash(text.utf8Data)
        guard !consumeIgnoredHash(hash), items.first?.contentHash != hash else { return }

        let item = ClipboardItem(
            kind: .text,
            sourceAppName: sourceApp?.name,
            sourceBundleIdentifier: sourceApp?.bundleIdentifier,
            previewText: Self.preview(for: trimmed),
            textContent: text,
            contentHash: hash,
            byteSize: text.utf8.count
        )

        insert(item)
    }

    func addImage(data: Data, previewText: String = "Image", sourceApp: ClipboardSourceApp?) {
        let hash = Self.hash(data)
        guard !consumeIgnoredHash(hash), items.first?.contentHash != hash else { return }

        // 图片不直接塞进 JSON，而是单独落盘。
        // JSON 里只记录文件名，避免历史文件越来越大。
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let item = ClipboardItem(
            kind: .image,
            sourceAppName: sourceApp?.name,
            sourceBundleIdentifier: sourceApp?.bundleIdentifier,
            previewText: previewText,
            imageFileName: fileName,
            contentHash: hash,
            byteSize: data.count
        )

        insert(item)
    }

    func addFiles(urls: [URL], sourceApp: ClipboardSourceApp?) {
        let normalizedURLs = urls.filter { $0.isFileURL }
        guard !normalizedURLs.isEmpty else { return }

        let references = normalizedURLs.map(Self.makeFileReference)
        let hashSource = references.map(\.originalPath).joined(separator: "\n")
        let hash = Self.hash(Data(hashSource.utf8))
        guard !consumeIgnoredHash(hash), items.first?.contentHash != hash else { return }

        let previewText = Self.filePreviewText(for: references.map(\.displayName))
        let totalByteSize = references.reduce(0) { partialResult, reference in
            partialResult + Int(reference.byteSize ?? 0)
        }

        let item = ClipboardItem(
            kind: .file,
            sourceAppName: sourceApp?.name,
            sourceBundleIdentifier: sourceApp?.bundleIdentifier,
            previewText: previewText,
            fileReferences: references,
            contentHash: hash,
            byteSize: totalByteSize
        )

        insert(item)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let imageFileName = item.imageFileName else { return nil }
        return imagesDirectoryURL.appendingPathComponent(imageFileName)
    }

    func fileURLs(for item: ClipboardItem) -> [URL] {
        guard item.kind == .file else { return [] }
        return item.fileReferences?.compactMap { $0.resolvedURL() } ?? []
    }

    func sourceIcon(for item: ClipboardItem) -> NSImage {
        // 优先按 bundle id 解析来源应用图标，失败时退回系统通用图标。
        if
            let bundleIdentifier = item.sourceBundleIdentifier,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return NSWorkspace.shared.icon(for: .application)
    }

    func filteredItems(query: String) -> [ClipboardItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }

        // 第一版搜索只做本地模糊匹配，不做 OCR 和更复杂索引。
        return items.filter { item in
            item.previewText.localizedCaseInsensitiveContains(term) ||
            item.textContent?.localizedCaseInsensitiveContains(term) == true
        }
    }

    func restoreToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let textContent = item.textContent else { return }
            ignoredHashes.insert(item.contentHash)
            pasteboard.setString(textContent, forType: .string)

        case .image:
            guard
                let url = imageURL(for: item),
                let image = NSImage(contentsOf: url)
            else { return }

            ignoredHashes.insert(item.contentHash)
            pasteboard.writeObjects([image])

        case .file:
            guard restoreFilesToPasteboard(for: item) else { return }
            ignoredHashes.insert(item.contentHash)
        }

        promoteRestoredItem(id: item.id)
    }

    func clearAll() {
        for item in items {
            removeFileIfNeeded(for: item)
        }

        items = []
        save()
    }

    func deleteItem(id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        removeFileIfNeeded(for: item)
        save()
    }

    func togglePinned(id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    private func insert(_ item: ClipboardItem) {
        // 新内容始终插入列表顶部。
        items.insert(item, at: 0)
        save()
        performCleanup()
    }

    private func promoteRestoredItem(id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        var restoredItem = items.remove(at: index)
        restoredItem = ClipboardItem(
            id: restoredItem.id,
            kind: restoredItem.kind,
            createdAt: .now,
            sourceAppName: restoredItem.sourceAppName,
            sourceBundleIdentifier: restoredItem.sourceBundleIdentifier,
            previewText: restoredItem.previewText,
            textContent: restoredItem.textContent,
            imageFileName: restoredItem.imageFileName,
            fileReferences: restoredItem.fileReferences,
            contentHash: restoredItem.contentHash,
            byteSize: restoredItem.byteSize,
            isPinned: restoredItem.isPinned
        )

        items.insert(restoredItem, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }

        do {
            let decoded = try JSONDecoder.pretty.decode([ClipboardItem].self, from: data)
            // 读取历史时，顺便把丢失图片文件的记录过滤掉。
            items = decoded.filter { item in
                guard item.kind == .image else { return true }
                guard let imageFileName = item.imageFileName else { return false }
                return fileManager.fileExists(atPath: imagesDirectoryURL.appendingPathComponent(imageFileName).path)
            }
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.pretty.encode(items)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            return
        }
    }

    private func performCleanup() {
        // 先按“保留天数”删除过期项。
        let expirationDate = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: .now) ?? .distantPast

        var retainedItems = items.filter { $0.createdAt >= expirationDate }
        var totalBytes = retainedItems.reduce(0) { $0 + $1.byteSize }
        let maxBytes = settings.maxStorageMB * 1_024 * 1_024

        // 再按“存储上限”删除最旧的内容，直到总大小回到限制内。
        while totalBytes > maxBytes, let removed = retainedItems.last {
            totalBytes -= removed.byteSize
            retainedItems.removeLast()
            removeFileIfNeeded(for: removed)
        }

        let removedIDs = Set(items.map(\.id)).subtracting(retainedItems.map(\.id))
        for item in items where removedIDs.contains(item.id) {
            removeFileIfNeeded(for: item)
        }

        items = retainedItems
        save()
    }

    private func removeFileIfNeeded(for item: ClipboardItem) {
        guard let url = imageURL(for: item), fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func restoreFilesToPasteboard(for item: ClipboardItem) -> Bool {
        guard item.kind == .file, let fileReferences = item.fileReferences else { return false }

        var scopedURLs: [URL] = []
        var activeScopedURLs: [URL] = []

        for fileReference in fileReferences {
            guard let url = fileReference.resolvedURL() else {
#if DEBUG
                print("[FileRestore] skip unresolved path=\(fileReference.originalPath)")
#endif
                continue
            }

            let accessGranted = url.startAccessingSecurityScopedResource()
#if DEBUG
            print("[FileRestore] access path=\(fileReference.originalPath) granted=\(accessGranted)")
#endif
            if accessGranted {
                activeScopedURLs.append(url)
            }
            scopedURLs.append(url)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = !scopedURLs.isEmpty && pasteboard.writeObjects(scopedURLs as [NSURL])

#if DEBUG
        print("[FileRestore] write count=\(scopedURLs.count) didWrite=\(didWrite)")
#endif

        for url in activeScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }

        return didWrite
    }

    private func consumeIgnoredHash(_ hash: String) -> Bool {
        ignoredHashes.remove(hash) != nil
    }

    private static func makeFileReference(from url: URL) -> ClipboardFileReference {
        // 如果是从剪贴板（NSItemProvider）读取的 URL，它通常是一个 Security-Scoped URL。
        // 在访问文件属性或创建持久化书签之前，必须先显式调用 startAccessingSecurityScopedResource。
        // 否则对于沙盒应用，可能会因为没有权限导致书签创建失败，重启后就无法访问文件了。
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? url.resourceValues(forKeys: [.nameKey, .isDirectoryKey, .fileSizeKey])
        let displayName = values?.name ?? url.lastPathComponent
        let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)

#if DEBUG
        print(
            "[FileBookmark] create path=\(url.path) scoped=\(isSecurityScoped) bookmark=\(bookmarkData != nil)"
        )
#endif

        return ClipboardFileReference(
            displayName: displayName,
            originalPath: url.path,
            bookmarkData: bookmarkData,
            isDirectory: values?.isDirectory ?? false,
            byteSize: values?.fileSize.map(Int64.init)
        )
    }

    private static func filePreviewText(for fileNames: [String]) -> String {
        guard let firstName = fileNames.first else { return "Files" }
        guard fileNames.count > 1 else { return firstName }
        return "\(firstName) +\(fileNames.count - 1)"
    }

    private static func applicationSupportURL() -> URL {
        // 这是 macOS 放应用私有持久化数据的标准目录。
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("bKit", isDirectory: true)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func preview(for text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(120)
            .description
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var pretty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
