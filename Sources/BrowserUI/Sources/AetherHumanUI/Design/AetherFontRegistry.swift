import AppKit
import CoreText
import SwiftUI

public enum AetherTextWeight: String, CaseIterable, Sendable {
    case body
    case emphasis
    case medium

    public var usWeightClass: Double {
        switch self {
        case .body: 400
        case .emphasis: 450
        case .medium: 500
        }
    }
}

public enum AetherFontRegistry {
    public static let families = ["Instrument Sans"]
    public static let fontExtensions = ["otf", "ttf", "ttc"]

    private static var installed = false
    private static var baseFace: String?
    private static var baseDescriptor: CTFontDescriptor?
    private static var weightAxisID: Int?

    public static func install() {
        guard !installed else { return }
        installed = true
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
        resolveVariableBase()
    }

    public static var hasBrandTypeface: Bool {
        install()
        return baseFace != nil
    }

    public static func faceName(for weight: AetherTextWeight) -> String? {
        install()
        return baseFace
    }

    public static var registeredFamily: String? {
        install()
        return families.first { NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil }
    }

    public static func font(_ size: CGFloat, _ weight: AetherTextWeight) -> Font {
        install()
        if let varied = variedFont(size: size, wght: weight.usWeightClass) { return varied }
        return Font(NSFont.systemFont(ofSize: size, weight: systemWeight(for: weight.usWeightClass)))
    }

    public static func symbolFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: AetherIconStyle.weight)
    }

    private static func bundledFontURLs() -> [URL] {
        let manager = FileManager.default
        var urls: [URL] = []
        for directory in fontDirectories() {
            guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            urls += entries.filter { fontExtensions.contains($0.pathExtension.lowercased()) }
        }
        return urls
    }

    private static func fontDirectories() -> [URL] {
        let manager = FileManager.default
        var directories: [URL] = []
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        if let moduleResources = Bundle.module.resourceURL { roots.append(moduleResources) }
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            roots.append(executable.deletingLastPathComponent())
        }
        roots.append(Bundle.main.bundleURL.deletingLastPathComponent())
        roots.append(Bundle.module.bundleURL)
        for root in roots {
            directories.append(root.appendingPathComponent("Fonts", isDirectory: true))
            directories.append(root.appendingPathComponent("AetherHumanUI/Resources/Fonts", isDirectory: true))
            directories.append(root.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true))
            directories.append(root.appendingPathComponent("Resources/Fonts", isDirectory: true))
            guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "bundle" {
                directories.append(entry.appendingPathComponent("Fonts", isDirectory: true))
                directories.append(entry.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true))
                directories.append(entry.appendingPathComponent("Resources/Fonts", isDirectory: true))
            }
        }
        return directories
    }

    private static func resolveVariableBase() {
        // Resolve the font directly from the SwiftPM resource URL. NSFontManager
        // can lag process registration of variable faces, even when CTFont sees them.
        for url in bundledFontURLs() {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                    as? [CTFontDescriptor] else { continue }
            for descriptor in descriptors {
                let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
                guard (CTFontCopyFamilyName(font) as String) == "Instrument Sans" else { continue }
                baseFace = CTFontCopyPostScriptName(font) as String
                baseDescriptor = descriptor
                weightAxisID = weightAxisIdentifier(of: font)
                return
            }
        }
        for family in families {
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let name = members.first?.first as? String,
                  let base = NSFont(name: name, size: 12) else { continue }
            baseFace = name
            baseDescriptor = CTFontCopyFontDescriptor(base as CTFont)
            weightAxisID = weightAxisIdentifier(of: base as CTFont)
            return
        }
        baseFace = nil
        baseDescriptor = nil
        weightAxisID = nil
    }

    private static func variedFont(size: CGFloat, wght: Double) -> Font? {
        guard let baseDescriptor else { return nil }
        guard let axis = weightAxisID else {
            return Font(CTFontCreateWithFontDescriptor(baseDescriptor, size, nil) as NSFont)
        }
        let variation = [kCTFontVariationAttribute as String: [axis: wght]] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(baseDescriptor, variation)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont)
    }

    private static func weightAxisIdentifier(of font: CTFont) -> Int? {
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return nil }
        for axis in axes {
            guard let name = axis[kCTFontVariationAxisNameKey as String] as? String,
                  name == "Weight",
                  let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? Int else { continue }
            return identifier
        }
        return nil
    }

    private static func systemWeight(for usWeight: Double) -> NSFont.Weight {
        let anchors: [(Double, CGFloat)] = [
            (300, NSFont.Weight.light.rawValue),
            (400, NSFont.Weight.regular.rawValue),
            (500, NSFont.Weight.medium.rawValue),
            (600, NSFont.Weight.semibold.rawValue),
            (700, NSFont.Weight.bold.rawValue)
        ]
        guard let first = anchors.first, let last = anchors.last else { return .regular }
        if usWeight <= first.0 { return NSFont.Weight(first.1) }
        if usWeight >= last.0 { return NSFont.Weight(last.1) }
        for index in 0..<(anchors.count - 1) {
            let lower = anchors[index], upper = anchors[index + 1]
            guard usWeight >= lower.0, usWeight <= upper.0 else { continue }
            let ratio = CGFloat((usWeight - lower.0) / (upper.0 - lower.0))
            return NSFont.Weight(lower.1 + (upper.1 - lower.1) * ratio)
        }
        return .regular
    }
}
