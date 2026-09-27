import WebKit

@MainActor
public final class AetherWebExtensionRegistry {
    public static let shared = AetherWebExtensionRegistry()
    private var controllers: [UUID: WKWebExtensionController] = [:]
    public var onCreate: ((UUID, WKWebExtensionController) -> Void)?

    private init() {}

    public func controller(profileID: UUID, store: WKWebsiteDataStore) -> WKWebExtensionController {
        if let existing = controllers[profileID] { return existing }
        WKWebExtension.MatchPattern.registerCustomURLScheme("chrome-extension")
        let configuration = WKWebExtensionController.Configuration(identifier: profileID)
        configuration.defaultWebsiteDataStore = store
        let webViewConfiguration = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        webViewConfiguration.websiteDataStore = store
        configuration.webViewConfiguration = webViewConfiguration
        let controller = WKWebExtensionController(configuration: configuration)
        controllers[profileID] = controller
        onCreate?(profileID, controller)
        return controller
    }
}
