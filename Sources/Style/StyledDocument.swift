import DOM
import Foundation

public struct StyledDocument: Sendable {
  public let document: DOMDocument
  public var styles: [NodeID: ComputedStyle]
  public let sourceMutationVersion: UInt64

  public init(document: DOMDocument, styles: [NodeID: ComputedStyle], sourceMutationVersion: UInt64)
  {
    self.document = document
    self.styles = styles
    self.sourceMutationVersion = sourceMutationVersion
  }

  public func style(for node: NodeID) -> ComputedStyle {
    styles[node] ?? ComputedStyle()
  }
}
