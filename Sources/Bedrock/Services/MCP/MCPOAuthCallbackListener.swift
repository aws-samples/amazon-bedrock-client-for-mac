import Foundation
import Network

/// Receives the SDK's ephemeral RFC 8252 redirect on IPv4 loopback only.
/// Requests must match both the redirect path and the authorization state.
@MainActor
final class MCPOAuthCallbackListener {
    private let redirect: URL
    private let state: String
    private let listener: NWListener
    private let completion: @MainActor (Result<URL, Error>) -> Void
    private var ready: CheckedContinuation<Void, Error>?
    private var connections: [UUID: NWConnection] = [:]
    private var stopped = false

    init(authorizationURL: URL,
         completion: @escaping @MainActor (Result<URL, Error>) -> Void) throws {
        let query = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = query.first(where: { $0.name == "redirect_uri" })?.value,
              let redirect = URL(string: value), redirect.scheme == "http", redirect.host == "127.0.0.1",
              let number = redirect.port, let port = NWEndpoint.Port(rawValue: UInt16(exactly: number) ?? 0),
              port.rawValue > 0, redirect.fragment == nil,
              let state = query.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw LocalOperationError.invalid("The sign-in redirect is not a valid loopback callback.")
        }
        self.redirect = redirect
        self.state = state
        self.completion = completion
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, !self.stopped else { return }
                    switch state {
                    case .ready:
                        let pending = self.ready; self.ready = nil
                        pending?.resume()
                    case .failed:
                        self.fail(LocalOperationError.unavailable("The local sign-in callback could not start. Retry sign-in."))
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func cancel() {
        guard !stopped else { return }
        stopped = true
        listener.cancel()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        let pending = ready; ready = nil
        pending?.resume(throwing: CancellationError())
    }

    private func fail(_ error: Error) {
        let pending = ready; ready = nil
        pending?.resume(throwing: error)
        completion(.failure(error))
        cancel()
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .global(qos: .userInitiated))
        receive(connection, id: id, data: Data())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, !self.stopped, self.connections[id] != nil else { return }
                var buffer = data
                if let bytes { buffer.append(bytes) }
                if buffer.count > 16_384 {
                    self.respond(connection, id: id, callback: nil)
                } else if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.respond(connection, id: id, callback: self.callback(from: buffer))
                } else if complete || error != nil {
                    self.connections.removeValue(forKey: id)?.cancel()
                } else {
                    self.receive(connection, id: id, data: buffer)
                }
            }
        }
    }

    private func callback(from data: Data) -> URL? {
        let line = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/"),
              let url = URL(string: String(parts[1]), relativeTo: redirect)?.absoluteURL,
              url.scheme == redirect.scheme, url.host == redirect.host, url.port == redirect.port,
              url.path == redirect.path, url.fragment == nil else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let states = query.filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else { return nil }
        return url
    }

    private func respond(_ connection: NWConnection, id: UUID, callback: URL?) {
        let body = callback == nil ? "Invalid sign-in callback." : "Sign-in received. You can return to Bedrock."
        let status = callback == nil ? "400 Bad Request" : "200 OK"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.connections.removeValue(forKey: id)?.cancel()
                if let callback, !self.stopped {
                    self.completion(.success(callback))
                    self.cancel()
                }
            }
        })
    }

    deinit { listener.cancel() }
}
