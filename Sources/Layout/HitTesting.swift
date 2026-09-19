import DOM
import EngineCore

public enum HitTesting {
  public static func node(at point: Point, in tree: LayoutTree) -> NodeID? {
    for id in tree.paintOrder.reversed() {
      guard let box = tree.boxes[id], box.frame.contains(point), box.style.display != .none else {
        continue
      }
      return id
    }
    return nil
  }
}
