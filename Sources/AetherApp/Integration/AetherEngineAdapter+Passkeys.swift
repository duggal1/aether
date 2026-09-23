import AetherHumanUI
import AuthenticationServices
import EngineRuntime
import Foundation
import LocalAuthentication

extension AetherEngineAdapter: BrowserPasskeyCapability {
  var passkeyDeviceConfigured: Bool {
    ASAuthorizationWebBrowserPublicKeyCredentialManager.isDeviceConfiguredForPasskeys
  }

  var passkeyLocalAuthAvailable: Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
  }

  func passkeyAuthorizationState() -> PasskeyAuthorizationState {
    switch ASAuthorizationWebBrowserPublicKeyCredentialManager()
      .authorizationStateForPlatformCredentials {
    case .authorized: return .authorized
    case .denied: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .unavailable
    }
  }

  func requestPasskeyAuthorization() async -> PasskeyAuthorizationState {
    await withCheckedContinuation { continuation in
      ASAuthorizationWebBrowserPublicKeyCredentialManager()
        .requestAuthorizationForPublicKeyCredentials { state in
          switch state {
          case .authorized: continuation.resume(returning: .authorized)
          case .denied: continuation.resume(returning: .denied)
          case .notDetermined: continuation.resume(returning: .notDetermined)
          @unknown default: continuation.resume(returning: .unavailable)
          }
        }
    }
  }
}
