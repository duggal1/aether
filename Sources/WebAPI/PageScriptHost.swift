import DOM
import Foundation
import JavaScript
import Networking
import Storage

public final class PageScriptHost {
  public let runtime: JSRuntime
  public let timers: JSTimerBridge
  public let loop = WebEventLoop()

  public init(document: DOMDocument, localStorage: LocalStorage, network: NetworkSession) {
    let runtime = JSRuntime(document: document, localStorage: localStorage)
    let timers = JSTimerBridge(runtime: runtime)
    runtime.timerHost = timers
    FetchBridge(network: network).install(into: runtime)
    self.runtime = runtime
    self.timers = timers
  }

  @discardableResult
  public func run(_ sources: [String]) -> [String] {
    runtime.runScripts(sources)
  }

  @discardableResult
  public func pump(now: Double = Date().timeIntervalSince1970 * 1000) -> Int {
    let fired = runtime.pumpTimers(now: now)
    runtime.drainCompletions()
    runtime.drainMicrotasks()
    return fired
  }

  public func drainTasks() async {
    await loop.drainTasks()
  }

  public var consoleOutput: [String] { runtime.consoleOutput }

  public var unhandledRejections: [String] { runtime.unhandledRejections }
}
