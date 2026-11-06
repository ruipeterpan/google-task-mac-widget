import Foundation

final class MemoryCredentials: AuthCredentialStorage {
    var values: [String: Data] = [:]
    func read(_ account: String) -> Data? { values[account] }
    func save(_ account: String, _ data: Data) throws { values[account] = data }
    func remove(_ account: String) { values.removeValue(forKey: account) }
}
final class MockGoogle: URLProtocol {
    static var responseCode = 400
    static var body = Data()
    static var transportError: URLError?
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let error = Self.transportError { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct AuthRecoveryTests {
    @MainActor static func main() async throws {
        let suite = "TaskGlass.AuthRecoveryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentials()
        try credentials.save("client", JSONEncoder().encode(OAuthClient(client_id: "fixture.apps.googleusercontent.com")))
        try credentials.save("tokens", JSONEncoder().encode(Tokens(access: "old-access-fixture", refresh: "refresh-fixture", expiry: Date().addingTimeInterval(-60))))
        let original = credentials.values
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGoogle.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockGoogle.body = Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)
        let auth = GoogleAuth(credentials: credentials, session: session, preferences: defaults)
        do { _ = try await auth.accessToken(); fatalError("Invalid token accepted") }
        catch let failure as GoogleServiceError { precondition(failure.requiresReauthentication) }
        precondition(auth.reauthenticationRequired && auth.signedIn && auth.client != nil)
        precondition(credentials.values == original, "Failure must preserve existing credentials")
        precondition(defaults.string(forKey: "googleLastAuthErrorCode") == "invalid_grant")
        do { _ = try await auth.accessToken(); fatalError("Blocked refresh retried") } catch {}
        precondition(MockGoogle.requests == 1, "Invalid grant must not be retried every minute")
        let restarted = GoogleAuth(credentials: credentials, session: session, preferences: defaults)
        precondition(restarted.reauthenticationRequired, "Reconnect state must survive relaunch")
        do { _ = try await restarted.accessToken(); fatalError("Relaunch retried invalid grant") } catch {}
        precondition(MockGoogle.requests == 1)
        auth.cancel()
        precondition(credentials.values == original && auth.reauthenticationRequired, "Cancelling must not erase old configuration")

        defaults.set(false, forKey: "googleReauthenticationRequired")
        let retryable = GoogleAuth(credentials: credentials, session: session, preferences: defaults)
        MockGoogle.transportError = URLError(.notConnectedToInternet)
        do { _ = try await retryable.accessToken(); fatalError("Transport error ignored") } catch {}
        precondition(!retryable.reauthenticationRequired && credentials.values == original)
        MockGoogle.transportError = nil
        MockGoogle.responseCode = 500
        MockGoogle.body = Data("unavailable".utf8)
        do { _ = try await retryable.accessToken(); fatalError("Server error ignored") } catch {}
        precondition(!retryable.reauthenticationRequired, "Outage must not force reauthentication")
        MockGoogle.responseCode = 400
        MockGoogle.body = Data(#"{"error":"invalid_client"}"#.utf8)
        do { _ = try await retryable.accessToken(); fatalError("Client error ignored") } catch {}
        precondition(!retryable.reauthenticationRequired, "Wrong client needs configuration repair, not an expired-account loop")
        MockGoogle.responseCode = 200
        MockGoogle.body = Data(#"{"access_token":"new-access-fixture","expires_in":3600}"#.utf8)
        let access = try await retryable.accessToken()
        let saved = try JSONDecoder().decode(Tokens.self, from: credentials.values["tokens"]!)
        precondition(access == "new-access-fixture" && saved.refresh == "refresh-fixture")
        precondition(credentials.values["client"] == original["client"])
        precondition(!retryable.reauthenticationRequired)
        let count = MockGoogle.requests
        _ = try await retryable.accessToken()
        precondition(MockGoogle.requests == count, "Valid access token should be reused")
        print("PASS: invalid-grant retry suppression across relaunch, preserved credentials, cancellation, retryable outages, bad-client classification and normal refresh")
    }
}
