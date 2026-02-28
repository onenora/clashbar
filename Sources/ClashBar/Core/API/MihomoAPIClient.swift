import Foundation

protocol MihomoAPITransporting: Sendable {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func requestNoResponse(_ endpoint: Endpoint) async throws
}

enum HTTPMethod: String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var foundationObject: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .bool(value):
            return value
        case let .double(value):
            return value
        case let .object(value):
            return value.mapValues(\.foundationObject)
        case let .array(value):
            return value.map(\.foundationObject)
        case .null:
            return NSNull()
        }
    }
}

enum Endpoint: Sendable {
    private static let proxyProvidersPath = "/providers/proxies"
    private static let ruleProvidersPath = "/providers/rules"

    case version
    case traffic
    case memory
    case logs(level: String?)

    case getConfigs
    case putConfigs(force: Bool)
    case patchConfigs(body: [String: JSONValue])

    case groupDelay(name: String, url: String, timeout: Int)

    case proxies
    case switchProxy(name: String, target: String)

    case proxyProviders
    case proxyProvider(name: String)
    case updateProxyProvider(name: String)
    case proxyProviderHealthcheck(name: String, url: String, timeout: Int)
    case proxyProviderProxyHealthcheck(provider: String, proxy: String, url: String, timeout: Int)

    case rules
    case ruleProviders
    case updateRuleProvider(name: String)

    case connections(interval: Int?)
    case closeAllConnections
    case closeConnection(id: String)
    case flushFakeIPCache
    case flushDNSCache

    var method: HTTPMethod {
        switch self {
        case .version, .traffic, .memory, .logs, .getConfigs, .groupDelay, .proxies, .proxyProviders,
                .proxyProvider, .proxyProviderHealthcheck, .proxyProviderProxyHealthcheck, .rules,
                .ruleProviders, .connections:
            return .get
        case .putConfigs, .switchProxy, .updateProxyProvider, .updateRuleProvider:
            return .put
        case .patchConfigs:
            return .patch
        case .closeAllConnections, .closeConnection:
            return .delete
        case .flushFakeIPCache, .flushDNSCache:
            return .post
        }
    }

    var path: String {
        switch self {
        case .version: return "/version"
        case .traffic: return "/traffic"
        case .memory: return "/memory"
        case .logs: return "/logs"
        case .getConfigs, .putConfigs, .patchConfigs: return "/configs"
        case let .groupDelay(name, _, _): return "/group/\(name.urlPathSegmentEscaped)/delay"
        case .proxies: return "/proxies"
        case let .switchProxy(name, _): return "/proxies/\(name.urlPathSegmentEscaped)"
        case .proxyProviders:
            return Self.proxyProvidersPath
        case let .proxyProvider(name), let .updateProxyProvider(name):
            return proxyProviderPath(name)
        case let .proxyProviderHealthcheck(name, _, _):
            return "\(proxyProviderPath(name))/healthcheck"
        case let .proxyProviderProxyHealthcheck(provider, proxy, _, _):
            return "\(proxyProviderPath(provider))/\(proxy.urlPathSegmentEscaped)/healthcheck"
        case .rules: return "/rules"
        case .ruleProviders:
            return Self.ruleProvidersPath
        case let .updateRuleProvider(name):
            return "\(Self.ruleProvidersPath)/\(name.urlPathSegmentEscaped)"
        case .connections, .closeAllConnections: return "/connections"
        case let .closeConnection(id): return "/connections/\(id.urlPathSegmentEscaped)"
        case .flushFakeIPCache: return "/cache/fakeip/flush"
        case .flushDNSCache: return "/cache/dns/flush"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .logs(level):
            return optionalQueryItem(name: "level", value: level)
        case let .putConfigs(force):
            return force ? [URLQueryItem(name: "force", value: "true")] : []
        case let .groupDelay(_, url, timeout):
            return healthcheckQueryItems(url: url, timeout: timeout)
        case let .proxyProviderHealthcheck(_, url, timeout), let .proxyProviderProxyHealthcheck(_, _, url, timeout):
            return healthcheckQueryItems(url: url, timeout: timeout)
        case let .connections(interval):
            return optionalQueryItem(name: "interval", value: interval.map(String.init))
        default:
            return []
        }
    }

    var body: Data? {
        switch self {
        case let .patchConfigs(body):
            return try? JSONSerialization.data(withJSONObject: body.mapValues(\.foundationObject))
        case let .switchProxy(_, target):
            return try? JSONSerialization.data(withJSONObject: ["name": target])
        default:
            return nil
        }
    }

    // Keep global requests responsive, but allow heavier latency-check endpoints enough time to complete.
    var timeoutInterval: TimeInterval {
        switch self {
        case .proxyProviderHealthcheck:
            return 180
        case let .groupDelay(_, _, timeout),
             let .proxyProviderProxyHealthcheck(_, _, _, timeout):
            return max(5, TimeInterval(timeout) / 1000.0 + 2)
        default:
            return 2
        }
    }

    private func proxyProviderPath(_ name: String) -> String {
        "\(Self.proxyProvidersPath)/\(name.urlPathSegmentEscaped)"
    }

    private func healthcheckQueryItems(url: String, timeout: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: "\(timeout)")
        ]
    }

    private func optionalQueryItem(name: String, value: String?) -> [URLQueryItem] {
        guard let value, !value.isEmpty else { return [] }
        return [URLQueryItem(name: name, value: value)]
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case statusCode(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Controller URL is invalid"
        case .invalidResponse:
            return "Invalid API response"
        case let .statusCode(code, message):
            return "API request failed (\(code)): \(message)"
        }
    }
}

final class MihomoAPIClient: MihomoAPITransporting, @unchecked Sendable {
    // Request building reads mutable credentials; guard with lock for thread safety.
    private let lock = NSLock()
    private let session: URLSession
    private let decoder = JSONDecoder()

    private(set) var controller: String
    private(set) var secret: String?

    init(controller: String, secret: String?, session: URLSession? = nil) {
        self.controller = controller
        self.secret = secret

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = 240
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            self.session = URLSession(configuration: config)
        }
    }

    func updateCredentials(controller: String, secret: String?) {
        lock.withLock {
            self.controller = controller
            self.secret = secret
        }
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await send(endpoint)
        return try decoder.decode(T.self, from: data)
    }

    func requestNoResponse(_ endpoint: Endpoint) async throws {
        _ = try await send(endpoint)
    }

    func makeTrafficWebSocketTask() throws -> URLSessionWebSocketTask {
        let request = try buildWebSocketRequest(for: .traffic)
        return session.webSocketTask(with: request)
    }

    func makeMemoryWebSocketTask() throws -> URLSessionWebSocketTask {
        let request = try buildWebSocketRequest(for: .memory)
        return session.webSocketTask(with: request)
    }

    func makeConnectionsWebSocketTask(interval: Int? = nil) throws -> URLSessionWebSocketTask {
        let request = try buildWebSocketRequest(for: .connections(interval: interval))
        return session.webSocketTask(with: request)
    }

    func makeLogsWebSocketTask(level: String? = nil) throws -> URLSessionWebSocketTask {
        let request = try buildWebSocketRequest(for: .logs(level: level))
        return session.webSocketTask(with: request)
    }

    private func send(_ endpoint: Endpoint) async throws -> Data {
        var lastError: Error?

        let maxAttempts = endpoint.method == .get ? 3 : 1

        for attempt in 0..<maxAttempts {
            do {
                let request = try buildRequest(for: endpoint)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                guard 200..<300 ~= http.statusCode else {
                    let message = String(data: data, encoding: .utf8) ?? "unknown error"
                    throw APIError.statusCode(http.statusCode, message)
                }
                return data
            } catch {
                lastError = error
                if attempt == maxAttempts - 1 { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        let (controller, secret) = lock.withLock {
            (self.controller, self.secret)
        }
        let url = try endpointURL(for: endpoint, controller: controller, webSocket: false)
        var request = authorizedRequest(url: url, secret: secret)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = endpoint.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func buildWebSocketRequest(for endpoint: Endpoint) throws -> URLRequest {
        let (controller, secret) = lock.withLock {
            (self.controller, self.secret)
        }
        let url = try endpointURL(for: endpoint, controller: controller, webSocket: true)
        return authorizedRequest(url: url, secret: secret)
    }

    private func endpointURL(for endpoint: Endpoint, controller: String, webSocket: Bool) throws -> URL {
        guard var components = URLComponents(string: normalizedControllerAddress(controller, webSocket: webSocket)) else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func authorizedRequest(url: URL, secret: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let secret, !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func normalizedControllerAddress(_ controller: String, webSocket: Bool) -> String {
        if webSocket {
            if controller.hasPrefix("ws://") || controller.hasPrefix("wss://") {
                return controller
            }
            if controller.hasPrefix("https://") {
                return controller.replacingOccurrences(of: "https://", with: "wss://")
            }
            if controller.hasPrefix("http://") {
                return controller.replacingOccurrences(of: "http://", with: "ws://")
            }
            return "ws://\(controller)"
        }

        if controller.hasPrefix("http://") || controller.hasPrefix("https://") {
            return controller
        }
        return "http://\(controller)"
    }
}

private extension String {
    var urlPathSegmentEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
