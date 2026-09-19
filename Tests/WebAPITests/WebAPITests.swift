import Foundation
import JavaScript
import Networking
import Testing
import WebAPI

@Test func timerBridgeFiresInOrder() throws {
  let runtime = JSRuntime()
  var now = Date().timeIntervalSince1970 * 1000
  let bridge = JSTimerBridge(runtime: runtime, now: { now })
  runtime.timerHost = bridge
  _ = try runtime.evaluate("log = [];")
  _ = try runtime.evaluate("setTimeout(function() { log.push('slow'); }, 10000);")
  _ = try runtime.evaluate("setTimeout(function() { log.push('fast'); }, 5000);")
  #expect(bridge.pendingCount == 2)
  #expect(bridge.nextFireAt != nil)
  now += 5000
  #expect(bridge.pump(now: now) == 1)
  #expect(try runtime.evaluate("log.join(',')").description == "fast")
  now += 5000
  #expect(bridge.pump(now: now) == 1)
  #expect(try runtime.evaluate("log.join(',')").description == "fast,slow")
  #expect(bridge.pendingCount == 0)
  #expect(bridge.nextFireAt == nil)
}

@Test func timerBridgeRepeatsAndClears() throws {
  let runtime = JSRuntime()
  var now = Date().timeIntervalSince1970 * 1000
  let bridge = JSTimerBridge(runtime: runtime, now: { now })
  runtime.timerHost = bridge
  _ = try runtime.evaluate("count = 0;")
  let id = try runtime.evaluate("setInterval(function() { count += 1; }, 5000);")
  #expect(id.description == "1")
  now += 5000
  #expect(bridge.pump(now: now) == 1)
  now += 5000
  #expect(bridge.pump(now: now) == 1)
  #expect(try runtime.evaluate("count").description == "2")
  _ = try runtime.evaluate("clearInterval(1);")
  #expect(bridge.pendingCount == 0)
  now += 60_000
  #expect(bridge.pump(now: now) == 0)
  #expect(try runtime.evaluate("count").description == "2")
}

@Test func runtimePumpTimersDelegatesToBridge() throws {
  let runtime = JSRuntime()
  var now = Date().timeIntervalSince1970 * 1000
  let bridge = JSTimerBridge(runtime: runtime, now: { now })
  runtime.timerHost = bridge
  _ = try runtime.evaluate("fired = false; setTimeout(function() { fired = true; }, 5000);")
  #expect(try runtime.evaluate("fired").description == "false")
  now += 60_000
  #expect(runtime.pumpTimers(now: now) == 1)
  #expect(try runtime.evaluate("fired").description == "true")
  _ = bridge
}

@Test func eventLoopRunsTasksThenMicrotasks() async throws {
  final class Order: @unchecked Sendable { var items: [String] = [] }
  let order = Order()
  let loop = WebEventLoop()
  await loop.queueTask { order.items.append("task-a") }
  await loop.queueTask {
    order.items.append("task-b")
    await loop.queueMicrotask { order.items.append("micro") }
  }
  #expect(await loop.hasPendingWork)
  #expect(await loop.pendingTasks == 2)
  await loop.drainTasks()
  #expect(order.items == ["task-a", "task-b", "micro"])
  #expect(await !loop.hasPendingWork)
}

@Test func fetchBridgeInstallsHook() throws {
  let runtime = JSRuntime()
  #expect(runtime.asyncFetch == nil)
  FetchBridge(network: NetworkSession()).install(into: runtime)
  #expect(runtime.asyncFetch != nil)
}
