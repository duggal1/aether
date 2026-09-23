import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

struct SessionAuthStateTests {
    @Test func unknownPageIsNotLoaded() async {
        let runtime = BrowserRuntime()
        #expect(await runtime.sessionAuthState(pageID: PageID(rawValue: 999_001)) == .notLoaded)
    }

    @Test func http401MeansReauthentication() {
        let classifier = SessionAuthClassifier()
        #expect(
            classifier.stateForCommittedPage(
                statusCode: 401, url: URL(string: "https://mail.example.com/"),
                historyCount: 3) == .reauthenticationRequired)
        #expect(
            classifier.stateForCommittedPage(
                statusCode: 403, url: URL(string: "https://mail.example.com/"),
                historyCount: 1) == .reauthenticationRequired)
    }

    @Test func ordinaryNavigationNeverClaimsAuthentication() {
        let classifier = SessionAuthClassifier()
        #expect(
            classifier.stateForCommittedPage(
                statusCode: 200, url: URL(string: "https://mail.example.com/"),
                historyCount: 3) == .navigated)
    }

    @Test func loginRedirectAfterHistoryMeansReauthentication() {
        let classifier = SessionAuthClassifier()
        #expect(
            classifier.stateForCommittedPage(
                statusCode: 200, url: URL(string: "https://accounts.example.com/login"),
                historyCount: 4) == .reauthenticationRequired)
    }

    @Test func firstVisitToLoginPageIsOrdinaryNavigation() {
        let classifier = SessionAuthClassifier()
        #expect(
            classifier.stateForCommittedPage(
                statusCode: 200, url: URL(string: "https://example.com/login"),
                historyCount: 1) == .navigated)
    }

    @Test func runtimeMapsStoredWebState() async {
        let runtime = BrowserRuntime()
        let id = PageID(rawValue: 999_002)
        await runtime.setWebStateForTests(
            id,
            WebPageState(
                sequence: 1, url: URL(string: "https://accounts.example.com/login"),
                title: "Sign in", viewport: Size(width: 800, height: 600),
                history: [
                    URL(string: "https://mail.example.com/")!,
                    URL(string: "https://accounts.example.com/login")!,
                ], historyIndex: 1, loading: false, loaded: true, contentReady: true, progress: 1,
                statusCode: 200, error: nil))
        #expect(await runtime.sessionAuthState(pageID: id) == .reauthenticationRequired)
    }

    @Test func runtimeMapsFailedWebState() async {
        let runtime = BrowserRuntime()
        let id = PageID(rawValue: 999_003)
        await runtime.setWebStateForTests(
            id,
            WebPageState(
                sequence: 1, url: nil, title: "", viewport: Size(width: 800, height: 600),
                history: [], historyIndex: -1, loading: false, loaded: false, contentReady: false,
                progress: 0,
                statusCode: 0, error: "timeout"))
        #expect(await runtime.sessionAuthState(pageID: id) == .failed)
    }
}
