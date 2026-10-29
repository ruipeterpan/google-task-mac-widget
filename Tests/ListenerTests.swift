import Foundation
import Network

@main struct ListenerTests {
    static func main() async throws {
        // Use the production factory: without a handler set before start this
        // fails with EINVAL, before any browser or Google service is involved.
        let listener = try makeOAuthListener { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                guard error == nil, let data,
                      String(decoding: data, as: UTF8.self).hasPrefix("GET /oauth2callback?code=test&state=test ") else {
                    connection.cancel(); return
                }
                let reply = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        defer { listener.cancel() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
        guard port != 0 else { fatalError("Listener did not obtain a callback port") }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/oauth2callback?code=test&state=test")!)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, String(decoding: data, as: UTF8.self) == "OK" else {
            fatalError("Loopback callback failed")
        }
        print("PASS: production OAuth listener starts and accepts an HTTP callback on loopback")
    }
}
