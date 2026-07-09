//
//  ClipboardHistoryFilePreviewViews.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI

// 这里集中放文件历史项的缩略图能力：
// 1. 图片/PDF 优先展示真实缩略图
// 2. 其他类型退回系统文件图标
// 3. 多文件复制时展示一个紧凑的缩略图条

struct FileThumbnailStripView: View {
    let fileReferences: [ClipboardFileReference]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(fileReferences.prefix(3))) { fileReference in
                FileThumbnailTileView(fileReference: fileReference)
            }
        }
    }
}

struct FileThumbnailPreviewView: View {
    let fileReference: ClipboardFileReference
    let frame: CGSize
    var iconPadding: CGFloat = 10

    @StateObject private var loader = FileThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileReference.originalPath))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(iconPadding)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .task(id: fileReference.id) {
            await loader.load(for: fileReference, targetSize: CGSize(width: frame.width * 2, height: frame.height * 2))
        }
    }
}

struct FileSystemIconView: View {
    let fileReference: ClipboardFileReference
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: fileReference.originalPath))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

private struct FileThumbnailTileView: View {
    let fileReference: ClipboardFileReference

    var body: some View {
        FileThumbnailPreviewView(
            fileReference: fileReference,
            frame: CGSize(width: 64, height: 64)
        )
    }
}

@MainActor
final class FileThumbnailLoader: ObservableObject {
    @Published var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    func load(for fileReference: ClipboardFileReference, targetSize: CGSize) async {
        if let cachedImage = Self.cache.object(forKey: fileReference.originalPath as NSString) {
            image = cachedImage
            return
        }

        image = await generateThumbnail(for: fileReference, targetSize: targetSize)

        if let image {
            Self.cache.setObject(image, forKey: fileReference.originalPath as NSString)
        }
    }

    private func generateThumbnail(for fileReference: ClipboardFileReference, targetSize: CGSize) async -> NSImage? {
        guard let url = fileReference.resolvedURL() else { return nil }

        if fileReference.isDirectory {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: targetSize,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
    }
}
