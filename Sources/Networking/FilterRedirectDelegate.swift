import ContentBlocker
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FilterRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  let blocker: FilterEngine
  let kind: BlockResourceKind
  let documentURL: URL?
  private let blocked = Mutex(false)
  var wasBlocked: Bool { blocked.withLock { $0 } }

  init(blocker: FilterEngine, kind: BlockResourceKind, documentURL: URL?) {
    self.blocker = blocker; self.kind = kind; self.documentURL = documentURL
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    guard let url = request.url,
      !blocker.decide(url: url, kind: kind, documentURL: documentURL).blocked else {
      blocked.withLock { $0 = true }
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
