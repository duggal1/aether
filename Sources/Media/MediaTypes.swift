import EngineCore
import Foundation

public enum MediaNetworkState: Int, Hashable, Sendable, Codable {
  case empty = 0
  case idle = 1
  case loading = 2
  case noSource = 3
}

public enum MediaReadyState: Int, Hashable, Sendable, Codable {
  case nothing = 0
  case metadata = 1
  case currentData = 2
  case futureData = 3
  case enoughData = 4
}

public enum MediaErrorCode: Int, Hashable, Sendable, Codable {
  case aborted = 1
  case network = 2
  case decode = 3
  case sourceNotSupported = 4
}

public struct MediaErrorInfo: Hashable, Sendable, Codable {
  public var code: MediaErrorCode
  public var message: String

  public init(code: MediaErrorCode, message: String) {
    self.code = code
    self.message = message
  }
}

public enum MediaEvent: String, Hashable, Sendable, Codable, CaseIterable {
  case loadstart
  case loadedmetadata
  case loadeddata
  case canplay
  case canplaythrough
  case playing
  case waiting
  case pause
  case ended
  case seeking
  case seeked
  case timeupdate
  case volumechange
  case ratechange
  case error
  case emptied
}

public struct MediaTrackInfo: Hashable, Sendable, Codable {
  public var kind: String
  public var label: String?
  public var language: String?

  public init(kind: String, label: String? = nil, language: String? = nil) {
    self.kind = kind
    self.label = label
    self.language = language
  }
}

public struct MediaElementState: Hashable, Sendable, Codable {
  public var nodeIndex: UInt32
  public var nodeGeneration: UInt32
  public var tag: String
  public var currentSrc: String?
  public var networkState: MediaNetworkState
  public var readyState: MediaReadyState
  public var seeking: Bool
  public var paused: Bool
  public var ended: Bool
  public var currentTime: Double
  public var duration: Double
  public var volume: Double
  public var muted: Bool
  public var playbackRate: Double
  public var videoWidth: Int
  public var videoHeight: Int
  public var error: MediaErrorInfo?
  public var audioTracks: [MediaTrackInfo]
  public var textTracks: [MediaTrackInfo]
  public var deliveredFrames: UInt64
  public var lastFrameTime: Double?

  public init(
    nodeIndex: UInt32, nodeGeneration: UInt32, tag: String, currentSrc: String? = nil,
    networkState: MediaNetworkState = .empty, readyState: MediaReadyState = .nothing,
    seeking: Bool = false, paused: Bool = true, ended: Bool = false, currentTime: Double = 0,
    duration: Double = .nan, volume: Double = 1, muted: Bool = false, playbackRate: Double = 1,
    videoWidth: Int = 0, videoHeight: Int = 0, error: MediaErrorInfo? = nil,
    audioTracks: [MediaTrackInfo] = [], textTracks: [MediaTrackInfo] = [],
    deliveredFrames: UInt64 = 0, lastFrameTime: Double? = nil
  ) {
    self.nodeIndex = nodeIndex
    self.nodeGeneration = nodeGeneration
    self.tag = tag
    self.currentSrc = currentSrc
    self.networkState = networkState
    self.readyState = readyState
    self.seeking = seeking
    self.paused = paused
    self.ended = ended
    self.currentTime = currentTime
    self.duration = duration
    self.volume = volume
    self.muted = muted
    self.playbackRate = playbackRate
    self.videoWidth = videoWidth
    self.videoHeight = videoHeight
    self.error = error
    self.audioTracks = audioTracks
    self.textTracks = textTracks
    self.deliveredFrames = deliveredFrames
    self.lastFrameTime = lastFrameTime
  }
}

public enum MediaAction: String, Hashable, Sendable, Codable {
  case play
  case pause
  case seek
  case setVolume
  case setMuted
  case setRate
  case load
}

public enum MediaEngineError: Error, Sendable {
  case unsupportedScheme(String)
  case noPlayableSource
  case backendUnavailable(String)
  case seekOutOfRange
  case elementNotFound
}
