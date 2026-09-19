import Foundation
import Testing
@testable import AetherCapture

private func temporaryParent() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Test func atomicPublicationAndDiscard() throws {
    let parent = temporaryParent()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = CaptureFolder(destination: parent.appendingPathComponent("kit"))
    try folder.prepare()
    try folder.write(Data("bytes".utf8), relative: "nested/file.txt")
    #expect(!FileManager.default.fileExists(atPath: folder.destination.path))
    try folder.finish()
    folder.discard()
    let written = try Data(contentsOf: folder.destination.appendingPathComponent("nested/file.txt"))
    #expect(written == Data("bytes".utf8))
    #expect(!FileManager.default.fileExists(atPath: folder.staging.path))
}

@Test func rejectsTraversalAndAbsolutePaths() throws {
    let parent = temporaryParent()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = CaptureFolder(destination: parent.appendingPathComponent("kit"))
    try folder.prepare()
    for path in ["../escape", "/absolute", "a/../../escape", "a\\escape"] {
        #expect(throws: (any Error).self) { try folder.write(Data(), relative: path) }
    }
    folder.discard()
    let remaining = try FileManager.default.contentsOfDirectory(atPath: parent.path)
    #expect(remaining.isEmpty)
}

@Test func publicationNeverOverwritesConcurrentDestination() throws {
    let parent = temporaryParent()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = CaptureFolder(destination: parent.appendingPathComponent("kit"))
    try folder.prepare()
    try FileManager.default.createDirectory(at: folder.destination, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: folder.destination.appendingPathComponent("sentinel"))
    #expect(throws: (any Error).self) { try folder.finish() }
    folder.discard()
    let sentinel = try Data(contentsOf: folder.destination.appendingPathComponent("sentinel"))
    #expect(sentinel == Data("keep".utf8))
}
