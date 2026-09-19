import EngineCore
import Storage
import Testing

@Test func localStorageIsPartitionedByOrigin() {
  let partition = StoragePartition(contextID: ContextID(rawValue: 1))
  partition.localStorage(for: "https://a.example").set("token", value: "a")
  partition.localStorage(for: "https://b.example").set("token", value: "b")
  #expect(partition.localStorage(for: "https://a.example").get("token") == "a")
  #expect(partition.localStorage(for: "https://b.example").get("token") == "b")
  #expect(partition.origins().count == 2)
}

@Test func storagePartitionSnapshotsRestore() {
  let partition = StoragePartition(contextID: ContextID(rawValue: 1))
  partition.localStorage(for: "https://a.example").set("token", value: "a")
  let snapshot = partition.snapshotAll()
  let restored = StoragePartition(contextID: ContextID(rawValue: 1))
  restored.restoreAll(snapshot)
  #expect(restored.localStorage(for: "https://a.example").get("token") == "a")
  #expect(restored.origins() == ["https://a.example"])
}
