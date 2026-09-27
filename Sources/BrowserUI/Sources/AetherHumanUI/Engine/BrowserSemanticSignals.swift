import Foundation

public enum BrowserSessionState: String, Codable, Hashable, Sendable {
    case active
    case loginRequired = "login_required"
    case sessionExpired = "session_expired"
    case notAuthenticationRelated = "not_authentication_related"
}

public enum BrowserOverlayKind: String, Codable, Hashable, Sendable {
    case cookieConsent = "cookie_consent"
    case newsletterSignup = "newsletter_signup"
    case ageGate = "age_gate"
    case paywall
    case promotion
    case requiredDialog = "required_dialog"
    case authentication
    case paymentConfirmation = "payment_confirmation"
    case destructiveConfirmation = "destructive_confirmation"
    case other
}

public enum BrowserAccessGateKind: String, Codable, Hashable, Sendable {
    case normalPage = "normal_page"
    case authenticationWall = "authentication_wall"
    case subscriptionPaywall = "subscription_paywall"
    case softPaywall = "soft_paywall"
    case permissionWall = "permission_wall"
    case botChallenge = "bot_challenge"
    case brokenContent = "broken_content"
}

public enum BrowserUploadIntent: String, Codable, Hashable, Sendable {
    case resume
    case contract
    case invoice
    case profilePhoto = "profile_photo"
    case spreadsheet
    case identityDocument = "identity_document"
    case other
}

public struct BrowserSemanticSignals: Equatable, Sendable {
    public let sessionState: BrowserSessionState?
    public let sessionConfidence: Double?
    public let overlayKind: BrowserOverlayKind?
    public let overlayConfidence: Double?
    public let overlaySafeToDismissProbability: Double?
    public let accessGateKind: BrowserAccessGateKind?
    public let accessGateConfidence: Double?
    public let phishingIdentityMismatchProbability: Double?
    public let relatedPageID: String?
    public let relatedPageConfidence: Double?
    public let semanticGroupID: String?
    public let uploadIntent: BrowserUploadIntent?
    public let uploadConfidence: Double?
    public let tabImportanceScore: Double?
    public let tabImportanceConfidence: Double?

    public init(
        sessionState: BrowserSessionState? = nil, sessionConfidence: Double? = nil,
        overlayKind: BrowserOverlayKind? = nil, overlayConfidence: Double? = nil,
        overlaySafeToDismissProbability: Double? = nil,
        accessGateKind: BrowserAccessGateKind? = nil, accessGateConfidence: Double? = nil,
        phishingIdentityMismatchProbability: Double? = nil, relatedPageID: String? = nil,
        relatedPageConfidence: Double? = nil, semanticGroupID: String? = nil,
        uploadIntent: BrowserUploadIntent? = nil, uploadConfidence: Double? = nil,
        tabImportanceScore: Double? = nil, tabImportanceConfidence: Double? = nil
    ) {
        self.sessionState = sessionState
        self.sessionConfidence = sessionConfidence
        self.overlayKind = overlayKind
        self.overlayConfidence = overlayConfidence
        self.overlaySafeToDismissProbability = overlaySafeToDismissProbability
        self.accessGateKind = accessGateKind
        self.accessGateConfidence = accessGateConfidence
        self.phishingIdentityMismatchProbability = phishingIdentityMismatchProbability
        self.relatedPageID = relatedPageID
        self.relatedPageConfidence = relatedPageConfidence
        self.semanticGroupID = semanticGroupID
        self.uploadIntent = uploadIntent
        self.uploadConfidence = uploadConfidence
        self.tabImportanceScore = tabImportanceScore
        self.tabImportanceConfidence = tabImportanceConfidence
    }
}
