//
//  ClipboardHistoryPresentationExtensions.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// 这里放历史窗口展示层会用到的辅助扩展：
// 1. 文本内容类型识别
// 2. CSS 颜色解析
// 3. 图片像素尺寸读取
// 它们都是纯展示支持，不参与数据存储结构。

enum DetectedTextContentType {
    case plain
    case link
    case color
}

extension ClipboardItem {
    var rowTimestampText: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent

        if Calendar.autoupdatingCurrent.isDateInToday(createdAt) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
        }

        return formatter.string(from: createdAt)
    }

    var detectedTextContentType: DetectedTextContentType {
        guard kind == .text else { return .plain }

        if colorPreview != nil {
            return .color
        }

        guard let text = normalizedTextContent else { return .plain }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return .plain
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = detector.firstMatch(in: text, options: [], range: range),
            match.resultType == .link,
            match.range == range
        else {
            return .plain
        }

        return .link
    }

    var colorPreview: Color? {
        guard kind == .text, let text = normalizedTextContent else { return nil }
        guard let nsColor = NSColor.cssColor(from: text) else { return nil }
        return Color(nsColor: nsColor)
    }

    var fileCount: Int {
        fileReferences?.count ?? 0
    }

    var totalFileByteSize: Int64 {
        Int64(fileReferences?.reduce(0) { $0 + Int($1.byteSize ?? 0) } ?? 0)
    }

    var primaryFileReference: ClipboardFileReference? {
        fileReferences?.first
    }

    var formattedByteSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteSize))
    }

    func imageDimensionsText(for imageURL: URL?) -> String? {
        guard kind == .image, let imageURL, let image = NSImage(contentsOf: imageURL) else { return nil }
        let size = image.pixelSize
        guard size.width > 0, size.height > 0 else { return nil }
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    var textCharacterCount: Int? {
        guard kind == .text, let normalizedTextContent else { return nil }
        return normalizedTextContent.count
    }

    func rowMetadataText(for imageURL: URL?, localizer: Localizer) -> String? {
        switch kind {
        case .image:
            guard let dimensions = imageDimensionsText(for: imageURL) else { return formattedByteSize }
            return "\(dimensions) | \(formattedByteSize)"
        case .file:
            guard let fileReferences, !fileReferences.isEmpty else { return nil }

            if fileReferences.count == 1 {
                let fileReference = fileReferences[0]
                if fileReference.isDirectory {
                    return localizer.historyFileFolderLabel
                }

                if fileReference.isImageFile {
                    let dimensions = fileReference.imageDimensionsText
                    let size = fileReference.byteSize.map(formattedByteSize(from:))

                    switch (dimensions, size) {
                    case let (dimensions?, size?):
                        return "\(dimensions) | \(size)"
                    case let (dimensions?, nil):
                        return dimensions
                    case let (nil, size?):
                        return size
                    case (nil, nil):
                        return nil
                    }
                }

                return fileReference.byteSize.map(formattedByteSize(from:)) ?? nil
            }

            let countText = "\(fileReferences.count) \(localizer.historyFileItemsLabel)"
            guard totalFileByteSize > 0 else { return countText }
            return "\(countText) | \(formattedByteSize(from: totalFileByteSize))"
        case .text:
            guard let textCharacterCount, textCharacterCount > 50 else { return nil }
            return "\(textCharacterCount) 字"
        }
    }

    var normalizedTextContent: String? {
        let source = (textContent ?? previewText).trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? nil : source
    }

    var detectedLinkURL: URL? {
        guard detectedTextContentType == .link, let text = normalizedTextContent else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = detector.firstMatch(in: text, options: [], range: range),
            match.resultType == .link,
            match.range == range
        else {
            return nil
        }

        return match.url
    }

    private func formattedByteSize(from byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}

extension NSColor {
    static func cssColor(from text: String) -> NSColor? {
        hexColor(from: text) ?? rgbColor(from: text) ?? hslColor(from: text)
    }

    private static func hexColor(from text: String) -> NSColor? {
        let sanitized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        let expanded: String
        switch sanitized.count {
        case 3:
            expanded = sanitized.reduce(into: "") { partialResult, character in
                partialResult.append(character)
                partialResult.append(character)
            } + "FF"
        case 4:
            expanded = sanitized.reduce(into: "") { partialResult, character in
                partialResult.append(character)
                partialResult.append(character)
            }
        case 6:
            expanded = sanitized + "FF"
        case 8:
            expanded = sanitized
        default:
            return nil
        }

        guard let value = UInt64(expanded, radix: 16) else { return nil }

        let red = CGFloat((value & 0xFF00_0000) >> 24) / 255
        let green = CGFloat((value & 0x00FF_0000) >> 16) / 255
        let blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
        let alpha = CGFloat(value & 0x0000_00FF) / 255

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func rgbColor(from text: String) -> NSColor? {
        guard let components = parseFunctionalColor(text, names: ["rgb", "rgba"]) else { return nil }
        guard components.count == 3 || components.count == 4 else { return nil }

        guard
            let red = rgbComponent(from: components[0]),
            let green = rgbComponent(from: components[1]),
            let blue = rgbComponent(from: components[2])
        else {
            return nil
        }

        let alpha = components.count == 4 ? alphaComponent(from: components[3]) : 1
        guard let alpha else { return nil }

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func hslColor(from text: String) -> NSColor? {
        guard let components = parseFunctionalColor(text, names: ["hsl", "hsla"]) else { return nil }
        guard components.count == 3 || components.count == 4 else { return nil }

        guard
            let hue = hueComponent(from: components[0]),
            let saturation = percentageComponent(from: components[1]),
            let lightness = percentageComponent(from: components[2])
        else {
            return nil
        }

        let alpha = components.count == 4 ? alphaComponent(from: components[3]) : 1
        guard let alpha else { return nil }

        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let hueSegment = hue / 60
        let secondary = chroma * (1 - abs(hueSegment.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2

        let rgb: (CGFloat, CGFloat, CGFloat)
        switch hueSegment {
        case 0..<1:
            rgb = (chroma, secondary, 0)
        case 1..<2:
            rgb = (secondary, chroma, 0)
        case 2..<3:
            rgb = (0, chroma, secondary)
        case 3..<4:
            rgb = (0, secondary, chroma)
        case 4..<5:
            rgb = (secondary, 0, chroma)
        default:
            rgb = (chroma, 0, secondary)
        }

        return NSColor(
            red: rgb.0 + match,
            green: rgb.1 + match,
            blue: rgb.2 + match,
            alpha: alpha
        )
    }

    private static func parseFunctionalColor(_ text: String, names: Set<String>) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let leftParenIndex = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return nil }

        let name = String(trimmed[..<leftParenIndex])
        guard names.contains(name) else { return nil }

        let start = trimmed.index(after: leftParenIndex)
        let inside = trimmed[start..<trimmed.index(before: trimmed.endIndex)]
        let normalized = inside
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "/", with: " ")

        let components = normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return components.isEmpty ? nil : components
    }

    private static func rgbComponent(from text: String) -> CGFloat? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return CGFloat(max(0, min(value, 100)) / 100)
        }

        guard let value = Double(text) else { return nil }
        return CGFloat(max(0, min(value, 255)) / 255)
    }

    private static func alphaComponent(from text: String) -> CGFloat? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return CGFloat(max(0, min(value, 100)) / 100)
        }

        guard let value = Double(text) else { return nil }
        return CGFloat(max(0, min(value, 1)))
    }

    private static func percentageComponent(from text: String) -> CGFloat? {
        guard text.hasSuffix("%"), let value = Double(text.dropLast()) else { return nil }
        return CGFloat(max(0, min(value, 100)) / 100)
    }

    private static func hueComponent(from text: String) -> CGFloat? {
        let cleaned = text.replacingOccurrences(of: "deg", with: "")
        guard let value = Double(cleaned) else { return nil }
        let normalized = value.truncatingRemainder(dividingBy: 360)
        return CGFloat(normalized >= 0 ? normalized : normalized + 360)
    }
}

extension NSImage {
    var pixelSize: CGSize {
        if let representation = representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        return size
    }
}

extension ClipboardFileReference {
    var formattedByteSizeText: String? {
        guard let byteSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }

    var isImageFile: Bool {
        guard let fileExtension else { return false }
        return UTType(filenameExtension: fileExtension)?.conforms(to: .image) ?? false
    }

    var isPDFFile: Bool {
        guard let fileExtension else { return false }
        return UTType(filenameExtension: fileExtension)?.conforms(to: .pdf) ?? false
    }

    var imageDimensionsText: String? {
        guard
            isImageFile,
            let image = loadImage()
        else {
            return nil
        }

        let size = image.pixelSize
        guard size.width > 0, size.height > 0 else { return nil }
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }
}
