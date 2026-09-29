import LocalAuthentication

/// Showing a saved password is proof of who is asking.
///
/// A password is handed to a page's own form without one: the page already
/// belongs to the site the password is kept for, and filling a field is what
/// signing in is. A password put where it can be read — on the screen, or in the
/// clipboard — belongs to whoever is looking, so it is the person the Mac
/// belongs to who is asked. Touch ID, the Apple Watch, or the account password,
/// whichever the Mac itself takes. A Mac that cannot be asked at all has nothing
/// to prove.
@MainActor
public enum AetherLocalAuth {
    public static func prove(_ reason: String) async -> Bool {
        let context = LAContext()
        var trouble: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &trouble) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
    }
}
