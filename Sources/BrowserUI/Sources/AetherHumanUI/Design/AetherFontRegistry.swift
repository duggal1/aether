import AppKit
import CoreText
import SwiftUI

public enum AetherTextWeight: String, CaseIterable, Sendable {
    case regular
    case emphasis

    public var usWeightClass: Double { self == .regular ? 400 : 450 }
}

public enum AetherFontRegistry {
    public static let families = ["Scto Grotesk A", "Scto Grotesk", "SctoGroteskA"]
    public static let fontExtensions = ["otf", "ttf", "ttc"]

    private static var installed = false
    private static var faces: [AetherTextWeight: String] = [:]

    public static func install() {
        guard !installed else { return }
        installed = true
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
        for weight in AetherTextWeight.allCases {
            if let face = resolveFace(weight) { faces[weight] = face }
        }
    }

    public static var hasBrandTypeface: Bool { faceName(for: .regular) != nil }

    public static func faceName(for weight: AetherTextWeight) -> String? {
        install()
        return faces[weight]
    }

    public static var registeredFamily: String? {
        install()
        return families.first { NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil }
    }

    public static func font(_ size: CGFloat, _ weight: AetherTextWeight) -> Font {
        if let name = faceName(for: weight) { return .custom(name, size: size).weight(.regular) }
        return Font(NSFont.systemFont(ofSize: size, weight: systemWeight(for: weight.usWeightClass)))
    }

    public static func symbolFont(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }

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
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            roots.append(executable.deletingLastPathComponent())
        }
        roots.append(Bundle.main.bundleURL.deletingLastPathComponent())
        for root in roots {
            directories.append(root.appendingPathComponent("Fonts", isDirectory: true))
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

    private static func resolveFace(_ weight: AetherTextWeight) -> String? {
        let target = systemWeight(for: weight.usWeightClass).rawValue
        for family in families {
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else { continue }
            let candidates = members.compactMap { member -> (name: String, trait: CGFloat)? in
                guard let name = member.first as? String,
                      let font = NSFont(name: name, size: 12) else { return nil }
                let traits = CTFontCopyTraits(font as CTFont) as NSDictionary
                guard let value = traits[kCTFontWeightTrait] as? NSNumber else { return nil }
                return (name, CGFloat(value.doubleValue))
            }
            guard !candidates.isEmpty else { continue }
            if weight == .emphasis,
               let next = candidates.filter({ $0.trait >= target }).min(by: { $0.trait < $1.trait }) {
                return next.name
            }
            return candidates.min { abs($0.trait - target) < abs($1.trait - target) }?.name
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
