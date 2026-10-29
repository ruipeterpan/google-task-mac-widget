import AppKit
import CryptoKit
import Network
import Security

// Network.framework requires this handler before start(queue:), even if the
// browser cannot reach the listener until after it becomes ready.
func makeOAuthListener(onConnection: @escaping (NWConnection) -> Void) throws -> NWListener {
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let server = try NWListener(using: params)
    server.newConnectionHandler = onConnection
    return server
}

// A desktop OAuth flow in the system browser, with PKCE, state validation and a loopback callback.
@MainActor final class GoogleAuth {
    private let service = "local.taskglass.google"
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var expectedState = ""
    private(set) var client: OAuthClient?
    private var tokens: Tokens?
    var signedIn: Bool { tokens != nil && client != nil }
    init() {
        if let data = read("client") { client = try? JSONDecoder().decode(OAuthClient.self, from: data) }
        if let data = read("tokens") { tokens = try? JSONDecoder().decode(Tokens.self, from: data) }
    }
    private func read(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
    private func save(_ account: String, _ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppError.message("Could not save credentials to Keychain.") }
        } else if update != errSecSuccess { throw AppError.message("Could not update Keychain credentials.") }
    }
    func importClient(_ data: Data) throws {
        let value = try OAuthClient.load(data)
        guard value.client_id.hasSuffix(".apps.googleusercontent.com") else { throw AppError.message("Choose the JSON file for a Google Desktop app OAuth client.") }
        try save("client", JSONEncoder().encode(value)); client = value
    }
    func disconnect() {
        cancel()
        for account in ["client", "tokens"] {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        }
        client = nil; tokens = nil
    }
    private func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func finish(_ result: Result<String, Error>) {
        let pending = continuation; continuation = nil
        listener?.cancel(); listener = nil; timeout?.cancel(); timeout = nil
        pending?.resume(with: result)
    }
    func cancel() { finish(.failure(AppError.message("Sign-in cancelled."))) }
    func signIn() async throws {
        guard let client else { throw AppError.message("Import your Google OAuth desktop client first.") }
        let verifier = random(); expectedState = random()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let server = try makeOAuthListener { [weak self] connection in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                connection.start(queue: .main)
                self.receive(connection, accumulated: Data())
            }
        }
        listener = server
        let port: UInt16 = try await withCheckedThrowingContinuation { ready in
            var resumed = false
            server.stateUpdateHandler = { state in
                Task { @MainActor in
                    guard !resumed else { return }
                    switch state {
                    case .ready:
                        resumed = true
                        if let port = server.port { ready.resume(returning: port.rawValue) }
                        else { server.cancel(); ready.resume(throwing: AppError.message("Sign-in listener started without a port. Please try again.")) }
                    case .failed(let error):
                        resumed = true; server.cancel(); self.listener = nil
                        ready.resume(throwing: AppError.message("Could not start the local sign-in callback: \(error.localizedDescription)"))
                    case .cancelled:
                        resumed = true; ready.resume(throwing: AppError.message("Sign-in cancelled."))
                    default: break
                    }
                }
            }
            server.start(queue: .main)
        }
        let redirect = "http://127.0.0.1:\(port)/oauth2callback"
        let code: String = try await withCheckedThrowingContinuation { pending in
            continuation = pending
            timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(180))
                if !Task.isCancelled { self.finish(.failure(AppError.message("Sign-in timed out. Please try again."))) }
            }
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = ["client_id": client.client_id, "redirect_uri": redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/tasks", "access_type": "offline", "prompt": "consent", "state": expectedState, "code_challenge": challenge, "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
            NSWorkspace.shared.open(url.url!)
        }
        var fields = ["client_id": client.client_id, "code": code, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier]
        fields["client_secret"] = client.client_secret
        try await exchange(fields, previousRefresh: nil)
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, done, error in
            Task { @MainActor in
                var all = accumulated; all.append(data ?? Data())
                guard all.count < 16384 else { connection.cancel(); return }
                guard let request = String(data: all, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if !done && error == nil { self.receive(connection, accumulated: all) } else { connection.cancel() }; return
                }
                let path = request.components(separatedBy: " ").dropFirst().first ?? ""
                let url = URLComponents(string: "http://127.0.0.1" + path)
                let query = url?.queryItems ?? []
                let state = query.first { $0.name == "state" }?.value
                let valid = url?.path == "/oauth2callback" && state == self.expectedState
                let code = query.first { $0.name == "code" }?.value
                let message = valid && code != nil ? "Connected. You can close this tab and return to TaskGlass." : "Sign-in was not completed. Return to TaskGlass and try again."
                let body = "<!doctype html><meta charset=utf-8><title>TaskGlass</title><h2>\(message)</h2>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                guard valid else { return }
                if let code { self.finish(.success(code)) } else { self.finish(.failure(AppError.message("Google sign-in was declined."))) }
            }
        }
    }
    private func exchange(_ fields: [String: String], previousRefresh: String?) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = formEncoded(fields)
        let (data, response) = try await URLSession.shared.data(for: request); try checkHTTP(data, response)
        struct Reply: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let refresh = reply.refresh_token ?? previousRefresh else { throw AppError.message("Google did not grant offline access. Sign in again.") }
        let value = Tokens(access: reply.access_token, refresh: refresh, expiry: Date().addingTimeInterval(reply.expires_in))
        try save("tokens", JSONEncoder().encode(value)); tokens = value
    }
    func accessToken() async throws -> String {
        guard let tokens, let client else { throw AppError.message("Connect Google Tasks first.") }
        if tokens.expiry.timeIntervalSinceNow > 60 { return tokens.access }
        var fields = ["client_id": client.client_id, "refresh_token": tokens.refresh, "grant_type": "refresh_token"]
        fields["client_secret"] = client.client_secret
        try await exchange(fields, previousRefresh: tokens.refresh)
        return self.tokens!.access
    }
}
