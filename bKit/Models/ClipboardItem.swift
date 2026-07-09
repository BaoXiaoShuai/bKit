//
//  ClipboardItem.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import Foundation
import AppKit

// 当前只支持两种历史内容：
// 1. 纯文本
// 2. 图片
enum ClipboardItemKind: String, Codable {
    case text
    case image
    case file
}

struct ClipboardFileReference: Identifiable, Codable, Equatable {
    var id: String { originalPath }

    let displayName: String
    let originalPath: String
    let bookmarkData: Data?
    let isDirectory: Bool
    let byteSize: Int64?

    var fileExtension: String? {
        let ext = URL(fileURLWithPath: originalPath).pathExtension
        return ext.isEmpty ? nil : ext
    }

    func resolvedURL() -> URL? {
        if let bookmarkData {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
#if DEBUG
                print("[FileBookmark] resolve success path=\(originalPath) stale=\(isStale)")
#endif
                return url
            } catch {
#if DEBUG
                print("[FileBookmark] resolve failed path=\(originalPath) error=\(error.localizedDescription)")
#endif
            }
        }

#if DEBUG
        print("[FileBookmark] fallback plain URL path=\(originalPath)")
#endif
        return URL(fileURLWithPath: originalPath)
    }

    func withScopedAccess<T>(_ body: (URL) -> T?) -> T? {
        guard let url = resolvedURL() else { return nil }
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return body(url)
    }

    func loadImage() -> NSImage? {
        withScopedAccess { url in
            NSImage(contentsOf: url)
        }
    }
}

// ClipboardItem 是一条历史记录的持久化模型。
// 它会被编码成 JSON 保存到本地。
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    let createdAt: Date
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let previewText: String
    let textContent: String?
    let imageFileName: String?
    let fileReferences: [ClipboardFileReference]?
    let contentHash: String
    let byteSize: Int
    var isPinned: Bool

    init(
        // 对文本来说，textContent 会保存完整内容；
        // 对图片来说，imageFileName 会指向本地 png 文件名。
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        createdAt: Date = .now,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        previewText: String,
        textContent: String? = nil,
        imageFileName: String? = nil,
        fileReferences: [ClipboardFileReference]? = nil,
        contentHash: String,
        byteSize: Int,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.previewText = previewText
        self.textContent = textContent
        self.imageFileName = imageFileName
        self.fileReferences = fileReferences
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case sourceAppName
        case sourceBundleIdentifier
        case previewText
        case textContent
        case imageFileName
        case fileReferences
        case contentHash
        case byteSize
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardItemKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        previewText = try container.decode(String.self, forKey: .previewText)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        fileReferences = try container.decodeIfPresent([ClipboardFileReference].self, forKey: .fileReferences)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        byteSize = try container.decode(Int.self, forKey: .byteSize)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

extension ClipboardItem {
    var containsFileReference: Bool {
        guard kind == .file else { return false }
        return fileReferences?.contains(where: { !$0.isDirectory }) == true
    }

    var containsOnlyFolderReferences: Bool {
        guard kind == .file, let fileReferences, !fileReferences.isEmpty else { return false }
        return fileReferences.allSatisfy(\.isDirectory)
    }
}
