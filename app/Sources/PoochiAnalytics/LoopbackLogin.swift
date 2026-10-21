import Foundation
import AppKit
import Network
#if SWIFT_PACKAGE
import PoochiCore
#endif

@MainActor
final class LoopbackLogin {
    private var listener: NWListener?
    private var pending: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]

    func authorize(attempt: OAuthAttempt, configuration: TikTokConfiguration) async throws -> String {
        try configuration.validate()
        let authorizationURL = try attempt.authorizationURL(configuration: configuration)
        let portNumber = URLComponents(string: configuration.redirectURI)!.port!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(portNumber))!)
        parameters.allowLocalEndpointReuse = false
        let server: NWListener
        do { server = try NWListener(using: parameters) }
        catch { throw PoochiError.listener("The local login listener could not start. Check the callback port in Settings.") }
        listener = server
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                server.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.pending != nil else { return }
                        switch state {
                        case .ready:
                            if !NSWorkspace.shared.open(authorizationURL) {
                                self.finish(.failure(PoochiError.listener("The browser could not open. Check your default browser and try again.")))
                            }
                        case .failed:
                            self.finish(.failure(PoochiError.listener("The callback port is unavailable. Close another running copy of Poochi Analytics or choose another port.")))
                        default: break
                        }
                    }
                }
                server.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.accept(connection, attempt: attempt, configuration: configuration) }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 180_000_000_000) }
                    catch { return }
                    self?.finish(.failure(PoochiError.listener("The login timed out. Click Connect to try again.")))
                }
                server.start(queue: .main)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() { finish(.failure(PoochiError.cancelled)) }

    private func accept(_ connection: NWConnection, attempt: OAuthAttempt, configuration: TikTokConfiguration) {
        guard pending != nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffered: Data(), attempt: attempt, configuration: configuration)
        Task { [weak self, weak connection] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if let self, self.connections.removeValue(forKey: id) != nil { connection?.cancel() }
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, buffered: Data,
                         attempt: OAuthAttempt, configuration: TikTokConfiguration) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.pending != nil else { connection.cancel(); return }
                var buffer = buffered
                if let data { buffer.append(data) }
                guard buffer.count <= 16_384, error == nil else {
                    self.connections.removeValue(forKey: id); connection.cancel(); return
                }
                if buffer.range(of: Data("\r\n\r\n".utf8)) == nil {
                    if complete { self.connections.removeValue(forKey: id); connection.cancel() }
                    else { self.receive(connection, id: id, buffered: buffer, attempt: attempt, configuration: configuration) }
                    return
                }
                let request = String(decoding: buffer, as: UTF8.self)
                let words = request.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
                guard words.count == 3, words[0] == "GET", words[1].hasPrefix("/"), !words[1].hasPrefix("//"),
                      let base = URLComponents(string: configuration.redirectURI),
                      let callback = URL(string: "http://127.0.0.1:\(base.port!)\(words[1])") else {
                    self.respond(connection, status: "400 Bad Request", text: "Invalid callback request.", completion: {})
                    self.connections.removeValue(forKey: id)
                    return
                }
                do {
                    let code = try attempt.authorizationCode(from: callback, redirectURI: configuration.redirectURI)
                    self.connections.removeValue(forKey: id)
                    self.respond(connection, status: "200 OK", text: "Connected. You can close this tab and return to Poochi Analytics.") {
                        self.finish(.success(code))
                    }
                } catch {
                    let isDenied = error as? PoochiError == .accessDenied
                    self.connections.removeValue(forKey: id)
                    self.respond(connection, status: "400 Bad Request", text: isDenied ? "Access was declined. Return to Poochi Analytics." : "This callback could not be verified.") {
                        if isDenied { self.finish(.failure(PoochiError.accessDenied)) }
                    }
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, text: String, completion: @escaping @MainActor () -> Void) {
        let body = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Poochi Analytics</title></head><body><h1>Poochi Analytics</h1><p>\(text)</p></body></html>"
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((headers + body).utf8), completion: .contentProcessed { _ in
            connection.cancel()
            Task { @MainActor in completion() }
        })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = pending else { return }
        pending = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        continuation.resume(with: result)
    }
}
