import XCTest
import Foundation
import AetherWebPrimitives

final class WebPrimitivesTests: XCTestCase {
    func testByteStreamRoundTrip() async throws {
        let stream = BoundedByteStream(capacity: 4)
        try await stream.write(Data("abcd".utf8))
        let first = try await stream.read()
        XCTAssertEqual(first, Data("abcd".utf8))
        await stream.finish()
        let final = try await stream.read()
        XCTAssertNil(final)
    }

    func testByteStreamBackpressureAndFailure() async throws {
        let stream = BoundedByteStream(capacity: 4)
        do { try await stream.write(Data("abcde".utf8)); XCTFail("Oversized chunk") }
        catch ByteStreamError.chunkTooLarge {}
        try await stream.write(Data("abcd".utf8))
        let blocked = Task { try await stream.write(Data("z".utf8)) }
        await Task.yield()
        let firstRead = try await stream.read()
        XCTAssertEqual(firstRead, Data("abcd".utf8))
        try await blocked.value
        let secondRead = try await stream.read()
        XCTAssertEqual(secondRead, Data("z".utf8))
        await stream.fail("broken")
        do { _ = try await stream.read(); XCTFail("Expected failure") }
        catch ByteStreamError.failed("broken") {}
    }

    func testMessageChannelCapacity() async throws {
        let channel = MessageChannel(maximumBytes: 2)
        try await channel.send(Data("ab".utf8))
        do { try await channel.send(Data("c".utf8)); XCTFail("Expected overflow") }
        catch ChannelError.overflow {}
        let message = await channel.receive()
        XCTAssertEqual(message?.payload, Data("ab".utf8))
        await channel.finish()
        let done = await channel.receive()
        XCTAssertNil(done)
    }

    @MainActor func testMicrotasksExecuteNestedJobs() {
        let queue = MicrotaskCheckpoint()
        var output: [Int] = []
        queue.enqueue {
            output.append(1)
            queue.enqueue { output.append(3) }
        }
        queue.enqueue { output.append(2) }
        XCTAssertEqual(queue.run(), 3)
        XCTAssertEqual(output, [1, 2, 3])
    }
}
