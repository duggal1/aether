import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

public struct MediaSource: Hashable, Sendable {
  public var url: URL
  public var mimeType: String?

  public init(url: URL, mimeType: String? = nil) {
    self.url = url
    self.mimeType = mimeType
  }
}

public enum MediaKind: String, Hashable, Sendable {
  case progressive
  case hls
  case unknown
}

public struct MediaCapability: Hashable, Sendable, Codable {
  public var hardwareH264: Bool
  public var hardwareHEVC: Bool
  public var hardwareVP9: Bool
  public var hardwareAV1: Bool
  public var hlsPlayback: Bool
  public var mediaSourceExtensions: Bool
  public var protectedPlayback: Bool

  public init(
    hardwareH264: Bool, hardwareHEVC: Bool, hardwareVP9: Bool, hardwareAV1: Bool,
    hlsPlayback: Bool, mediaSourceExtensions: Bool, protectedPlayback: Bool
  ) {
    self.hardwareH264 = hardwareH264
    self.hardwareHEVC = hardwareHEVC
    self.hardwareVP9 = hardwareVP9
    self.hardwareAV1 = hardwareAV1
    self.hlsPlayback = hlsPlayback
    self.mediaSourceExtensions = mediaSourceExtensions
    self.protectedPlayback = protectedPlayback
  }
}

public enum MediaFormat {
  public static func kind(of url: URL, mimeType: String? = nil) -> MediaKind {
    if let mime = mimeType?.lowercased() {
      if mime.contains("mpegurl") || mime.contains("x-mpegurl") { return .hls }
      if mime.hasPrefix("video/") || mime.hasPrefix("audio/") { return .progressive }
    }
    let path = url.pathExtension.lowercased()
    if path == "m3u8" { return .hls }
    if ["mp4", "m4v", "mov", "mp3", "m4a", "aac", "wav", "caf", "webm", "mkv"].contains(path) {
      return .progressive
    }
    return .unknown
  }

  public static func supportedSchemes(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    if ["http", "https"].contains(scheme) { return true }
    if url.isFileURL { return true }
    if scheme == "blob" || scheme == "data" { return false }
    return false
  }

  public static func currentCapability() -> MediaCapability {
    MediaCapability(
      hardwareH264: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264),
      hardwareHEVC: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
      hardwareVP9: VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9),
      hardwareAV1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
      hlsPlayback: true,
      mediaSourceExtensions: false,
      protectedPlayback: false
    )
  }

  public static func canPlayType(mime: String, tag: String) -> String {
    let normalized = mime.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let type = normalized.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
    let video = tag.lowercased() == "video"
    switch type {
    case "video/mp4", "video/m4v", "video/quicktime", "video/x-m4v":
      return video ? "probably" : ""
    case "audio/mp3", "audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/wav",
      "audio/x-wav", "audio/x-caf":
      return video ? "" : "probably"
    case "application/x-mpegurl", "application/vnd.apple.mpegurl":
      return video ? "probably" : "maybe"
    case "video/webm", "audio/webm":
      return "maybe"
    default:
      return ""
    }
  }

  public static func playable(_ url: URL) async -> Bool {
    guard supportedSchemes(url) else { return false }
    let asset = AVURLAsset(url: url)
    guard let playable = try? await asset.load(.isPlayable) else { return false }
    return playable
  }
}
