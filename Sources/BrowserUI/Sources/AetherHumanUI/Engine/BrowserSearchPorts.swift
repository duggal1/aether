import Foundation

@MainActor
public protocol BrowserSearchSuggesting: AnyObject {
    func searchCompletions(prefix: String, limit: Int, providerEndpoint: URL?) async throws -> [String]
    func warmSearchCompletions(providerEndpoint: URL?) async
}
