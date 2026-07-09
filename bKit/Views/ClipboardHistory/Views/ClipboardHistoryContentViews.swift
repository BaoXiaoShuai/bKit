//
//  ClipboardHistoryContentViews.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import SwiftUI

// 这个文件集中放历史主窗口里的内容型视图：
// 1. 列表行
// 2. 悬浮详情内容
// 不放状态调度和面板控制逻辑，方便后续单独迭代视觉。

struct ClipboardRowView: View {
    private static let sourceIconSize: CGFloat = 18
    private static let sourceLabelSpacing: CGFloat = 10
    private static let maxImagePreviewHeight: CGFloat = 100

    let item: ClipboardItem
    let imageURL: URL?
    let fileURLs: [URL]
    let sourceIcon: NSImage
    let isSelected: Bool
    let localizer: Localizer
    let textFontSize: CGFloat
    let imagePreviewHeight: CGFloat
    let onHoverChanged: (Bool, CGRect) -> Void

    @State private var rowFrame: CGRect = .zero
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: Self.sourceLabelSpacing) {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.sourceIconSize, height: Self.sourceIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(item.sourceAppName ?? localizer.historyUnknownSource)
                    .font(.system(size: 14, weight: .semibold))

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.historyPrimary)
                }

                Spacer()

                Text(item.rowTimestampText)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
            }

            HStack(alignment: .top, spacing: Self.sourceLabelSpacing) {
                Color.clear
                    .frame(width: Self.sourceIconSize, height: 1)

                contentArea

                Spacer()
            }

            if let metadataText = item.rowMetadataText(for: imageURL, localizer: localizer) {
                HStack(alignment: .top, spacing: Self.sourceLabelSpacing) {
                    Color.clear
                        .frame(width: Self.sourceIconSize, height: 1)

                    Text(metadataText)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
                        .lineLimit(1)

                    Spacer()
                }
            }

        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(backgroundFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1)
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(ScreenFrameReader(frame: $rowFrame))
        .onHover { hovering in
            isHovered = hovering
            DispatchQueue.main.async {
                onHoverChanged(hovering, rowFrame)
            }
        }
        .onChange(of: rowFrame) { _, frame in
            guard isHovered else { return }
            DispatchQueue.main.async {
                onHoverChanged(true, frame)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            if let colorPreview = item.colorPreview {
                Circle()
                    .fill(colorPreview)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
            } else {
                EmptyView()
            }

        case .image:
            if let imageURL, let image = NSImage(contentsOf: imageURL) {
                imagePreviewView(image)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
                    .frame(width: 240, height: Self.maxImagePreviewHeight)
            }

        case .file:
            if let fileReferences = item.fileReferences, !fileReferences.isEmpty {
                FileThumbnailStripView(fileReferences: fileReferences)
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch item.kind {
        case .text:
            HStack(alignment: .top, spacing: 12) {
                preview

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.previewText)
                        .font(.system(size: textFontSize, weight: .medium))
                        .lineLimit(4)
                }
            }

        case .image:
            preview

        case .file:
            if let imageFileReference = singleImageFileReference {
                VStack(alignment: .leading, spacing: 6) {
                    fileImagePreview(for: imageFileReference)

                    Text(imageFileReference.displayName)
                        .font(.system(size: textFontSize, weight: .medium))
                        .lineLimit(2)

                    Text(imageFileReference.originalPath)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.86) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if item.fileCount > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(multipleFileTitleText)
                        .font(.system(size: textFontSize, weight: .medium))
                        .lineLimit(3)

                    Text(multipleFileCountText)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.86) : .secondary)
                        .lineLimit(1)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    preview

                    VStack(alignment: .leading, spacing: 6) {
                        Text(fileTitleText)
                            .font(.system(size: textFontSize, weight: .medium))
                            .lineLimit(item.fileCount > 1 ? 3 : 2)

                        if let fileReferences = item.fileReferences, !fileReferences.isEmpty {
                            Text(filePathText(for: fileReferences))
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.86) : .secondary)
                                .lineLimit(item.fileCount > 1 ? 2 : 1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var multipleFileTitleText: String {
        guard let fileReferences = item.fileReferences, !fileReferences.isEmpty else {
            return item.previewText
        }

        return fileReferences
            .prefix(2)
            .map(\.displayName)
            .joined(separator: "\n")
    }

    private var multipleFileCountText: String {
        "\(item.fileCount) 个文件"
    }

    @ViewBuilder
    private func fileImagePreview(for fileReference: ClipboardFileReference) -> some View {
        if let image = fileReference.loadImage() {
            imagePreviewView(image)
        } else {
            preview
        }
    }

    private func imagePreviewView(_ image: NSImage) -> some View {
        let isWide = isWideImage(image)
        let previewHeight = resolvedImagePreviewHeight(for: image)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(
                maxWidth: isWide ? .infinity : 100,
                maxHeight: previewHeight,
                alignment: .leading
            )
    }

    private var fileTitleText: String {
        guard let fileReferences = item.fileReferences, !fileReferences.isEmpty else {
            return item.previewText
        }

        if fileReferences.count == 1, let fileReference = fileReferences.first {
            return fileReference.displayName
        }

        return fileReferences
            .prefix(2)
            .map(\.displayName)
            .joined(separator: "\n")
    }

    private func filePathText(for fileReferences: [ClipboardFileReference]) -> String {
        if fileReferences.count == 1, let fileReference = fileReferences.first {
            return fileReference.originalPath
        }

        return fileReferences
            .prefix(2)
            .map(\.originalPath)
            .joined(separator: "\n")
    }

    private var singleImageFileReference: ClipboardFileReference? {
        guard
            item.kind == .file,
            let fileReferences = item.fileReferences,
            fileReferences.count == 1,
            let fileReference = fileReferences.first,
            !fileReference.isDirectory,
            fileReference.isImageFile
        else {
            return nil
        }

        return fileReference
    }

    private var backgroundFillColor: Color {
        if isSelected {
            return .historyPrimary
        }

        if isHovered {
            return Color.white.opacity(0.58)
        }

        return .clear
    }

    private var borderColor: Color {
        if isSelected {
            return Color.historyPrimary.opacity(0.30)
        }

        if isHovered {
            return Color.black.opacity(0.08)
        }

        return .clear
    }

    private func resolvedImagePreviewHeight(for image: NSImage) -> CGFloat {
        min(Self.maxImagePreviewHeight, max(1, image.size.height), imagePreviewHeight)
    }

    private func isWideImage(_ image: NSImage) -> Bool {
        let size = image.pixelSize
        return size.width > size.height
    }
}

// 悬浮详情卡只负责渲染内容，不负责显示时机和窗口定位。
struct HoverPreviewContentView: View {
    let item: ClipboardItem
    let imageURL: URL?
    let fileURLs: [URL]
    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewBody
            VStack(spacing: 0) {
                metadataRow(title: localizer.historyPreviewLastCopied, value: item.createdAt.formatted(date: .numeric, time: .standard))
                Divider()
                metadataRow(title: primaryDetailTitle, value: primaryDetailValue)
                if showsImageSizeMetadata {
                    Divider()
                    metadataRow(title: localizer.historyPreviewImageSize, value: imageSizeMetadataValue)
                }
                Divider()
                metadataRow(title: localizer.historyPreviewContentType, value: contentTypeText)
            }
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch item.kind {
        case .text:
            HoverPreviewTextCard(text: item.textContent ?? item.previewText)

        case .image:
            if let imageURL, let image = NSImage(contentsOf: imageURL) {
                HoverPreviewImageView(image: image)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
            }

        case .file:
            if let fileReferences = item.fileReferences, !fileReferences.isEmpty {
                if let fileReference = singleImageFileReference, let image = fileReference.loadImage() {
                    HoverPreviewSingleImageFileCard(
                        image: image,
                        fileReference: fileReference
                    )
                } else if let fileReference = singlePDFFileReference {
                    HoverPreviewSingleFilePreviewCard(fileReference: fileReference)
                } else if let fileReference = singleFileReference {
                    HoverPreviewSingleFileInfoCard(fileReference: fileReference, localizer: localizer)
                } else {
                    HoverPreviewFileListCard(fileReferences: fileReferences, localizer: localizer)
                }
            }
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var primaryDetailValue: String {
        switch item.kind {
        case .text:
            return "\(item.textContent?.count ?? item.previewText.count)"
        case .image:
            return item.imageDimensionsText(for: imageURL) ?? "-"
        case .file:
            if let fileReference = singleImageFileReference {
                return fileReference.imageDimensionsText ?? "-"
            }
            return "\(item.fileCount)"
        }
    }

    private var primaryDetailTitle: String {
        switch item.kind {
        case .text:
            return localizer.historyPreviewCharacters
        case .image:
            return localizer.historyPreviewDimensions
        case .file:
            if singleImageFileReference != nil {
                return localizer.historyPreviewDimensions
            }
            return localizer.historyPreviewFileCount
        }
    }

    private var showsImageSizeMetadata: Bool {
        item.kind == .image || singleImageFileReference != nil
    }

    private var imageSizeMetadataValue: String {
        if let fileReference = singleImageFileReference {
            return fileReference.formattedByteSizeText ?? "-"
        }

        return item.formattedByteSize
    }

    private var contentTypeText: String {
        switch item.kind {
        case .image:
            return localizer.historyPreviewTypeImage
        case .file:
            if let fileReference = singleFileReference, fileReference.isDirectory {
                return localizer.historyFileFolderLabel
            }
            return item.containsOnlyFolderReferences ? localizer.historyFileFolderLabel : localizer.historyPreviewTypeFile
        case .text:
            switch item.detectedTextContentType {
            case .plain:
                return localizer.historyPreviewTypeText
            case .link:
                return localizer.historyPreviewTypeLink
            case .color:
                return localizer.historyPreviewTypeColor
            }
        }
    }

    private var singleFileReference: ClipboardFileReference? {
        guard
            item.kind == .file,
            let fileReferences = item.fileReferences,
            fileReferences.count == 1
        else {
            return nil
        }

        return fileReferences.first
    }

    private var singlePreviewableFileReference: ClipboardFileReference? {
        guard let fileReference = singleFileReference else { return nil }
        guard !fileReference.isDirectory, fileReference.isImageFile || fileReference.isPDFFile else { return nil }
        return fileReference
    }

    private var singleImageFileReference: ClipboardFileReference? {
        guard let fileReference = singlePreviewableFileReference, fileReference.isImageFile else { return nil }
        return fileReference
    }

    private var singlePDFFileReference: ClipboardFileReference? {
        guard let fileReference = singlePreviewableFileReference, fileReference.isPDFFile else { return nil }
        return fileReference
    }
}

private struct HoverPreviewTextCard: View {
    let text: String

    @State private var measuredTextHeight: CGFloat = 0

    private let horizontalPadding: CGFloat = 14
    private let verticalPadding: CGFloat = 14
    private let minContentHeight: CGFloat = 56
    private let maxContentHeight: CGFloat = 224

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .background(textHeightReader)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .frame(height: resolvedHeight)
        .background(cardShape.fill(Color.white))
        .overlay(cardShape.stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var resolvedHeight: CGFloat {
        min(max(measuredTextHeight + (verticalPadding * 2), minContentHeight), maxContentHeight)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var textHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: HoverPreviewMeasuredHeightKey.self, value: proxy.size.height)
        }
        .onPreferenceChange(HoverPreviewMeasuredHeightKey.self) { height in
            guard abs(measuredTextHeight - height) > 0.5 else { return }
            DispatchQueue.main.async {
                measuredTextHeight = height
            }
        }
    }
}

private struct HoverPreviewImageView: View {
    let image: NSImage

    private let wideImageMaxHeight: CGFloat = 260
    private let compactImageHeight: CGFloat = 100
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(
                maxWidth: isWideImage ? .infinity : nil,
                maxHeight: isWideImage ? wideImageMaxHeight : compactImageHeight,
                alignment: .center
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var isWideImage: Bool {
        let size = image.pixelSize
        return size.width > size.height
    }
}

private struct HoverPreviewSingleImageFileCard: View {
    let image: NSImage
    let fileReference: ClipboardFileReference

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HoverPreviewImageView(image: image)

            VStack(alignment: .leading, spacing: 6) {
                Text(fileReference.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Text(fileReference.originalPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct HoverPreviewFileListCard: View {
    let fileReferences: [ClipboardFileReference]
    let localizer: Localizer

    private let maxListHeight: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(fileReferences.enumerated()), id: \.element.id) { index, fileReference in
                    fileRow(for: fileReference)

                    if index < fileReferences.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxHeight: maxListHeight)
        .background(cardShape.fill(Color.white))
        .overlay(cardShape.stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private func fileRow(for fileReference: ClipboardFileReference) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FileSystemIconView(fileReference: fileReference, size: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(fileReference.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Text(fileTypeText(for: fileReference))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(fileReference.originalPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func fileTypeText(for fileReference: ClipboardFileReference) -> String {
        fileReference.isDirectory ? localizer.historyFileFolderLabel : localizer.historyPreviewTypeFile
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

private struct HoverPreviewSingleFilePreviewCard: View {
    let fileReference: ClipboardFileReference

    private let maxPreviewHeight: CGFloat = 220

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            FileThumbnailPreviewView(
                fileReference: fileReference,
                frame: CGSize(width: 260, height: maxPreviewHeight),
                iconPadding: 20
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: maxPreviewHeight)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardShape.fill(Color.white))
        .overlay(cardShape.stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
}

private struct HoverPreviewSingleFileInfoCard: View {
    let fileReference: ClipboardFileReference
    let localizer: Localizer

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FileSystemIconView(fileReference: fileReference, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(fileReference.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Text(fileReference.isDirectory ? localizer.historyFileFolderLabel : localizer.historyPreviewTypeFile)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(fileReference.originalPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(cardShape.fill(Color.white))
        .overlay(cardShape.stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
}

private struct HoverPreviewMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
