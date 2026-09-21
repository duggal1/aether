import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal

public final class PlayerBackend: @unchecked Sendable {
  public typealias EventHandler = @Sendable (MediaEvent, MediaElementSnapshot) -> Void

  public struct MediaElementSnapshot: Sendable {
    public var currentTime: Double = 0
    public var duration: Double = .nan
    public var rate: Double = 0
    public var volume: Double = 1
    public var muted: Bool = false
    public var statusReady: Bool = false
    public var videoWidth: Int = 0
    public var videoHeight: Int = 0
    public var audioTracks: [MediaTrackInfo] = []
    public var textTracks: [MediaTrackInfo] = []
    public var error: MediaErrorInfo? = nil

    public init() {}
  }

  private let lock = NSLock()
  private let callbacks = DispatchQueue(label: "aether.media-backend")
  private var player: AVPlayer?
  private var videoOutput: AVPlayerItemVideoOutput?
  private var observations: [NSKeyValueObservation] = []
  private var notifications: [NSObjectProtocol] = []
  private var timeObserver: Any?
  private var snapshot = MediaElementSnapshot()
  private var deliveredFrames: UInt64 = 0
  private var lastFrameTime: Double?
  private var latestPixelBuffer: CVPixelBuffer?
  private let textureCache = VideoTextureCache()
  private var onEvent: EventHandler?
  private var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?

  public init() {}

  public func setEventHandler(_ handler: EventHandler?) {
    lock.withLock { onEvent = handler }
  }

  public func setFrameHandler(_ handler: (@Sendable (CVPixelBuffer, CMTime) -> Void)?) {
    lock.withLock { onFrame = handler }
  }

  private func emit(_ event: MediaEvent) {
    let (handler, snap) = lock.withLock { (onEvent, snapshot) }
    handler?(event, snap)
  }

  private func mutate(_ change: (inout MediaElementSnapshot) -> Void) {
    lock.withLock { change(&snapshot) }
  }

  public func load(url: URL) {
    onMain {
      self.teardownItem()
      self.mutate {
        $0 = MediaElementSnapshot()
        $0.volume = self.player?.volume.double ?? 1
        $0.muted = self.player?.isMuted ?? false
      }
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: CVPixelBufferAttributes(
        pixelFormatTypes: [CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA)]))
      let item = AVPlayerItem(url: url)
      item.add(output)
      let player: AVPlayer
      if let existing = self.player {
        player = existing
        existing.replaceCurrentItem(with: item)
      } else {
        player = AVPlayer(playerItem: item)
        player.volume = self.lock.withLock { self.snapshot.volume }.float
        player.isMuted = self.lock.withLock { self.snapshot.muted }
        self.player = player
      }
      self.videoOutput = output
      self.observe(item: item, player: player)
      self.emit(.loadstart)
    }
  }

  public func play() {
    onMain { self.player?.play() }
  }

  public func pause() {
    onMain { self.player?.pause() }
  }

  public func seek(to seconds: Double, completion: (@Sendable (Bool) -> Void)? = nil) {
    onMain { [self] in
      guard let player = self.player, let item = player.currentItem else {
        completion?(false)
        return
      }
      let duration = item.duration.seconds
      guard seconds.isFinite, seconds >= 0,
        !duration.isNaN, seconds <= max(duration, 0)
      else {
        completion?(false)
        return
      }
      self.emit(.seeking)
      let target = CMTime(seconds: seconds, preferredTimescale: 600)
      player.seek(
        to: target, toleranceBefore: .zero, toleranceAfter: .zero
      ) { [weak self] finished in
        guard let self else { return }
        self.callbacks.async {
          if finished { self.emit(.seeked) }
          completion?(finished)
        }
      }
    }
  }

  public func setVolume(_ volume: Double) {
    let clamped = min(max(volume, 0), 1)
    mutate { $0.volume = clamped }
    onMain { self.player?.volume = clamped.float }
    emit(.volumechange)
  }

  public func setMuted(_ muted: Bool) {
    mutate { $0.muted = muted }
    onMain { self.player?.isMuted = muted }
    emit(.volumechange)
  }

  public func setRate(_ rate: Double) {
    let clamped = rate == 0 ? 0 : min(max(rate, 0.25), 4)
    mutate { $0.rate = clamped }
    onMain {
      if clamped == 0 { self.player?.pause() }
      else { self.player?.rate = clamped.float }
    }
    emit(.ratechange)
  }

  public func pollFrame() {
    DispatchQueue.main.async { [weak self] in self?.pollFrameOnMain() }
  }

  private func pollFrameOnMain() {
    assertMain()
    guard let output = videoOutput, let item = player?.currentItem,
      output.hasNewPixelBuffer(forItemTime: item.currentTime())
    else { return }
    let frame = output.pixelBufferAndDisplayTime(forItemTime: item.currentTime())
    guard frame.pixelBuffer != nil else { return }
    let time = item.currentTime().seconds
    frame.pixelBuffer?.withUnsafeBuffer { buffer in
      let handler = lock.withLock { () -> (@Sendable (CVPixelBuffer, CMTime) -> Void)? in
        latestPixelBuffer = buffer
        deliveredFrames += 1
        lastFrameTime = time.isFinite ? time : nil
        return onFrame
      }
      handler?(buffer, item.currentTime())
    }
  }

  public func currentVideoFrame(device: MTLDevice) -> MediaVideoFrame? {
    pollFrame()
    guard let buffer = lock.withLock({ latestPixelBuffer }) else { return nil }
    return textureCache.frame(for: buffer, device: device)
  }

  public func state() -> (MediaElementSnapshot, UInt64, Double?) {
    lock.withLock { (snapshot, deliveredFrames, lastFrameTime) }
  }

  public func shutdown() {
    onMain { self.teardownItem() }
  }

  private func teardownItem() {
    assertMain()
    player?.pause()
    observations.removeAll()
    for token in notifications {
      NotificationCenter.default.removeObserver(token)
    }
    notifications.removeAll()
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }
    videoOutput = nil
    lock.withLock { latestPixelBuffer = nil }
  }

  private static func trackKinds(of item: AVPlayerItem) -> [String] {
    let tracks = item.tracks
    if Thread.isMainThread {
      return MainActor.assumeIsolated {
        tracks.compactMap { $0.assetTrack?.mediaType.rawValue }
      }
    }
    return DispatchQueue.main.sync {
      MainActor.assumeIsolated {
        tracks.compactMap { $0.assetTrack?.mediaType.rawValue }
      }
    }
  }

  private func observe(item: AVPlayerItem, player: AVPlayer) {
    assertMain()
    observations = [
      item.observe(\.status, options: [.new]) { [weak self] observed, _ in
        let status = observed.status
        let duration = observed.duration.seconds
        let size = observed.presentationSize
        let kinds = Self.trackKinds(of: observed)
        let failure = observed.error.map { String(describing: $0) }
        guard let self else { return }
        self.callbacks.async {
          self.itemStatusChanged(
            status: status, duration: duration, size: size, trackKinds: kinds,
            failure: failure)
        }
      },
      player.observe(\.status, options: [.new]) { [weak self] observed, _ in
        let failed = observed.status == .failed
        let message = observed.error.map { String(describing: $0) }
        guard let self else { return }
        self.callbacks.async { self.playerStatusChanged(failed: failed, message: message) }
      },
      player.observe(\.rate, options: [.new]) { [weak self] observed, _ in
        let rate = Double(observed.rate)
        guard let self else { return }
        self.callbacks.async { self.rateChanged(rate: rate) }
      },
      item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observed, _ in
        let empty = observed.isPlaybackBufferEmpty
        guard let self else { return }
        self.callbacks.async {
          if empty { self.emit(.waiting) }
        }
      },
      item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observed, _ in
        let keepUp = observed.isPlaybackLikelyToKeepUp
        guard let self else { return }
        self.callbacks.async {
          if keepUp { self.emit(.canplaythrough) }
        }
      },
    ]
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: callbacks
    ) { [weak self] _ in
      self?.tick()
    }
    notifications = [
      NotificationCenter.default.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil
      ) { [weak self] _ in
        guard let self else { return }
        self.callbacks.async { self.emit(.ended) }
      },
      NotificationCenter.default.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: nil
      ) { [weak self] note in
        let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
          .map { String(describing: $0) } ?? "playback failed"
        guard let self else { return }
        self.callbacks.async {
          self.mutate {
            $0.error = MediaErrorInfo(code: .decode, message: message)
          }
          self.emit(.error)
        }
      },
    ]
  }

  private func itemStatusChanged(
    status: AVPlayerItem.Status, duration: Double, size: CGSize, trackKinds: [String],
    failure: String?
  ) {
    switch status {
    case .readyToPlay:
      mutate {
        $0.statusReady = true
        $0.duration = duration.isFinite ? duration : .nan
        $0.videoWidth = Int(size.width)
        $0.videoHeight = Int(size.height)
        $0.audioTracks = trackKinds.filter { $0 == AVMediaType.audio.rawValue }.map { _ in
          MediaTrackInfo(kind: "main")
        }
        $0.textTracks = trackKinds.filter {
          $0 == AVMediaType.subtitle.rawValue || $0 == AVMediaType.closedCaption.rawValue
        }.map { _ in MediaTrackInfo(kind: "subtitles") }
        if let failure {
          $0.error = MediaErrorInfo(code: .network, message: failure)
        }
      }
      let snap = lock.withLock { snapshot }
      if snap.error != nil { emit(.error) }
      else {
        emit(.loadedmetadata)
        emit(.loadeddata)
        emit(.canplay)
      }
    case .failed:
      mutate {
        $0.error = MediaErrorInfo(code: .network, message: failure ?? "item failed")
      }
      emit(.error)
    case .unknown:
      break
    @unknown default:
      break
    }
  }

  private func playerStatusChanged(failed: Bool, message: String?) {
    guard failed else { return }
    mutate {
      $0.error = MediaErrorInfo(code: .decode, message: message ?? "player failed")
    }
    emit(.error)
  }

  private func rateChanged(rate: Double) {
    mutate { $0.rate = rate }
    emit(rate == 0 ? .pause : .playing)
  }

  private func tick() {
    let time = mainSync { [weak self] in self?.playerTime() ?? .nan }
    guard time.isFinite else { return }
    mutate { $0.currentTime = time }
    emit(.timeupdate)
  }

  private func playerTime() -> Double {
    assertMain()
    return player?.currentTime().seconds ?? .nan
  }

  private func onMain(_ work: @escaping @Sendable () -> Void) {
    if Thread.isMainThread { work() }
    else { DispatchQueue.main.sync(execute: work) }
  }

  private func mainSync<T: Sendable>(_ work: @escaping @Sendable () -> T) -> T {
    if Thread.isMainThread { return work() }
    return DispatchQueue.main.sync(execute: work)
  }

  private func assertMain() {
    assert(Thread.isMainThread)
  }
}

private extension Float {
  var double: Double { Double(self) }
}

private extension Double {
  var float: Float { Float(self) }
}
