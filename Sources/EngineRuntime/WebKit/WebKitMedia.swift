import DOM
import EngineCore
import Foundation
import Media

extension WebKitPage {
  private var mediaProjection: String { """
    n => {
      const q = n instanceof HTMLVideoElement ? n.getVideoPlaybackQuality?.() : null;
      const tracks = list => Array.from(list ?? []).map(t =>
        ({kind:t.kind ?? '',label:t.label ?? null,language:t.language ?? null}));
      return {
        nodeIndex:globalThis.__aetherDOM.describe(n).index,
        nodeGeneration:\(generation),
        tag:n.localName,
        currentSrc:n.currentSrc || null,
        networkState:n.networkState,
        readyState:n.readyState,
        seeking:n.seeking,
        paused:n.paused,
        ended:n.ended,
        currentTime:Number.isFinite(n.currentTime) ? n.currentTime : 0,
        duration:Number.isFinite(n.duration) ? n.duration : 0,
        volume:n.volume,
        muted:n.muted,
        playbackRate:n.playbackRate,
        videoWidth:n.videoWidth ?? 0,
        videoHeight:n.videoHeight ?? 0,
        error:n.error ? {code:n.error.code,message:n.error.message} : null,
        audioTracks:tracks(n.audioTracks),
        textTracks:tracks(n.textTracks),
        deliveredFrames:q?.totalVideoFrames ?? 0,
        lastFrameTime:null
      };
    }
    """ }

  func mediaStates() async throws -> [MediaElementState] {
    try await decode([MediaElementState].self, domScript("""
      JSON.stringify(Array.from(document.querySelectorAll('video,audio')).slice(0,1000)
        .map(\(mediaProjection)))
      """))
  }

  func mediaState(_ node: NodeID) async throws -> MediaElementState {
    guard node.version == generation else { throw BrowserRuntimeError.nodeNotFound(node) }
    let state = try await decode(MediaElementState?.self, domScript("""
      (() => {
        const n = globalThis.__aetherDOM.get(\(node.index));
        return JSON.stringify(n?.isConnected && n instanceof HTMLMediaElement
          ? (\(mediaProjection))(n) : null);
      })()
      """))
    guard let state else { throw BrowserRuntimeError.nodeNotFound(node) }
    return state
  }

  func mediaAction(_ node: NodeID, action: MediaAction, time: Double?, value: Double?,
    muted: Bool?, rate: Double?) async throws
  {
    let body: String
    switch action {
    case .play:
      body = "n.play()"
    case .pause:
      body = "n.pause()"
    case .seek:
      guard let time, time.isFinite, time >= 0 else {
        throw BrowserRuntimeError.invalidNavigation("Valid seek time is required")
      }
      body = "n.currentTime = \(time)"
    case .setVolume:
      guard let value, value.isFinite, (0...1).contains(value) else {
        throw BrowserRuntimeError.invalidNavigation("Volume must be between 0 and 1")
      }
      body = "n.volume = \(value)"
    case .setMuted:
      body = "n.muted = \(muted ?? true)"
    case .setRate:
      guard let rate, rate.isFinite, rate > 0 else {
        throw BrowserRuntimeError.invalidNavigation("Positive playback rate is required")
      }
      body = "n.playbackRate = \(rate)"
    case .load:
      body = "n.load()"
    }
    try await nodeAction(node, body: """
      if (!(n instanceof HTMLMediaElement)) throw new Error('Node is not media');
      \(body);
      """)
  }
}

extension BrowserRuntime {
  public func mediaStates(pageID: PageID) async throws -> [MediaElementState] {
    _ = try requirePage(pageID)
    return try await webPage(pageID).mediaStates()
  }

  public func mediaCommand(
    pageID: PageID, node: NodeID, action: MediaAction, time: Double? = nil,
    value: Double? = nil, muted: Bool? = nil, rate: Double? = nil
  ) async throws -> MediaElementState {
    _ = try requirePage(pageID)
    let page = try await webPage(pageID)
    _ = try await page.mediaState(node)
    try await page.mediaAction(node, action: action, time: time, value: value,
      muted: muted, rate: rate)
    let predicate: (MediaElementState) -> Bool
    let timeout: TimeInterval
    switch action {
    case .play:
      predicate = { !$0.paused }
      timeout = 10
    case .pause:
      predicate = { $0.paused }
      timeout = 3
    case .seek:
      predicate = { abs($0.currentTime - (time ?? 0)) < 0.35 }
      timeout = 5
    default:
      return try await page.mediaState(node)
    }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let state = try await page.mediaState(node)
      if predicate(state) { return state }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw BrowserRuntimeError.invalidNavigation("Media action did not settle")
  }
}
