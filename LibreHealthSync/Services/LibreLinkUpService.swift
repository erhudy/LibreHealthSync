import CryptoKit
import Foundation

nonisolated enum LibreLinkUpError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case rateLimited(retryAfterSeconds: Int?)
    case incorrectCredentials
    case authenticationFailed(String)
    case sessionExpired
    case termsOfUseRequired
    case networkError(Error)
    case decodingError(Error)
    case noData
    case unsupportedRegion(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let statusCode):
            return "LibreLinkUp returned HTTP \(statusCode)."
        case .rateLimited(let retryAfterSeconds):
            if let seconds = retryAfterSeconds {
                return "LibreLinkUp is rate limiting this account. Try again in \(seconds) seconds."
            }
            return "LibreLinkUp is rate limiting this account. Try again in a few minutes."
        case .incorrectCredentials:
            return "Incorrect email or password."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .sessionExpired:
            return "Your LibreLinkUp session expired and could not be renewed. Please log out and log in again."
        case .termsOfUseRequired:
            return "You must accept the Terms of Use in the LibreLinkUp app before continuing."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .noData:
            return "No data returned from server."
        case .unsupportedRegion(let region):
            return "Your account is on the \(region.uppercased()) LibreLinkUp server, which this app doesn't support yet."
        }
    }
}

nonisolated protocol GlucoseDataProvider: Sendable {
    func fetchConnections() async throws -> [Connection]
    func fetchGraphData(connectionId: String) async throws -> GraphData
}

actor LibreLinkUpService: GlucoseDataProvider {
    private let keychain = KeychainService()
    private let session: URLSession

    private var region: LibreLinkUpRegion
    private var token: String?
    private var userId: String?

    nonisolated private static let apiHeaders: [String: String] = [
        "product": "llu.android",
        "version": "4.16.0",
        "Content-Type": "application/json",
        "Accept": "application/json",
    ]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        // Initialize with defaults; actual values loaded lazily on first use
        self.region = .us
        self.token = nil
        self.userId = nil
    }
    
    // Load cached credentials on first access
    private var hasLoadedCache = false
    
    private func loadCachedCredentials() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        
        self.region = keychain.getRegion() ?? .us
        self.token = keychain.getToken()
        self.userId = keychain.getUserId()
    }

    // MARK: - Login

    struct LoginResult {
        let userId: String
        let token: String
        let region: LibreLinkUpRegion
    }

    func login(email: String, password: String, region: LibreLinkUpRegion) async throws -> LoginResult {
        loadCachedCredentials()
        self.region = region

        let body = LoginRequest(email: email, password: password)
        let data = try await post(path: "/llu/auth/login", body: body, authenticated: false)

        let response: LoginResponse
        do {
            response = try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            throw LibreLinkUpError.decodingError(error)
        }

        // Status 4 = Terms of Use must be accepted
        if response.status == 4 {
            throw LibreLinkUpError.termsOfUseRequired
        }

        // Some lockouts are reported in the JSON status rather than the HTTP status.
        if response.status == 429 || response.status == 430 {
            throw LibreLinkUpError.rateLimited(retryAfterSeconds: response.data?.lockout)
        }

        // Regional redirect: the region can appear under data or at the top level.
        // Only the regions in LibreLinkUpRegion are supported; anything else is a
        // clear "not supported yet" rather than a confusing missing-ticket error.
        let redirectedTo = (response.data?.redirect == true ? response.data?.region : nil)
            ?? (response.redirect == true ? response.region : nil)
        if let regionString = redirectedTo {
            guard let redirectRegion = LibreLinkUpRegion.allCases.first(where: {
                $0.rawValue.contains(regionString.lowercased())
            }) else {
                throw LibreLinkUpError.unsupportedRegion(regionString)
            }
            // Retry login with the correct regional server (guarding against a
            // redirect back to the server we just used, which would loop forever).
            guard redirectRegion != region else {
                throw LibreLinkUpError.authenticationFailed("Server redirected to \(redirectRegion.displayName) repeatedly.")
            }
            return try await login(email: email, password: password, region: redirectRegion)
        }

        // Status 2 ("notAuthenticated") is how LibreLinkUp reports a bad password.
        if response.status == 2 {
            throw LibreLinkUpError.incorrectCredentials
        }

        guard response.status == 0 else {
            let detail = response.data?.message.map { " (\($0))" } ?? ""
            throw LibreLinkUpError.authenticationFailed("LibreLinkUp returned status \(response.status)\(detail).")
        }

        // Extract auth ticket — could be at data.authTicket or top-level ticket
        guard let ticket = response.data?.authTicket ?? response.ticket else {
            throw LibreLinkUpError.authenticationFailed("No auth ticket in response.")
        }

        guard let user = response.data?.user else {
            throw LibreLinkUpError.authenticationFailed("No user info in response.")
        }

        // Store credentials
        self.token = ticket.token
        self.userId = user.id
        self.region = region

        keychain.saveEmail(email)
        keychain.savePassword(password)
        keychain.saveToken(ticket.token)
        keychain.saveUserId(user.id)
        keychain.saveRegion(region)

        return LoginResult(userId: user.id, token: ticket.token, region: region)
    }

    // MARK: - Connections

    func fetchConnections() async throws -> [Connection] {
        loadCachedCredentials()
        let data = try await get(path: "/llu/connections")

        let response: ConnectionsResponse
        do {
            response = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
        } catch {
            throw LibreLinkUpError.decodingError(error)
        }

        updateTicketIfPresent(response.ticket)

        guard let connections = response.data else {
            throw LibreLinkUpError.noData
        }

        return connections
    }

    // MARK: - Graph Data (History)

    func fetchGraphData(connectionId: String) async throws -> GraphData {
        loadCachedCredentials()
        let data = try await get(path: "/llu/connections/\(connectionId)/graph")

        let response: GraphResponse
        do {
            response = try JSONDecoder().decode(GraphResponse.self, from: data)
        } catch {
            throw LibreLinkUpError.decodingError(error)
        }

        updateTicketIfPresent(response.ticket)

        guard let graphData = response.data else {
            throw LibreLinkUpError.noData
        }

        return graphData
    }

    // MARK: - Re-login (token refresh)

    func relogin() async throws {
        loadCachedCredentials()
        guard let email = keychain.getEmail(),
              let password = keychain.getPassword()
        else {
            throw LibreLinkUpError.authenticationFailed("No stored credentials for re-login.")
        }
        _ = try await login(email: email, password: password, region: region)
    }

    // MARK: - Private Helpers

    private func updateTicketIfPresent(_ ticket: AuthTicket?) {
        if let ticket = ticket {
            self.token = ticket.token
            keychain.saveToken(ticket.token)
        }
    }

    private func accountIdHeader() -> String? {
        guard let userId = self.userId else { return nil }
        let data = Data(userId.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func buildRequest(url: URL, method: String, authenticated: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (key, value) in Self.apiHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if authenticated, let token = self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if authenticated, let accountId = accountIdHeader() {
            request.setValue(accountId, forHTTPHeaderField: "Account-Id")
        }

        return request
    }

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: region.baseURL) else {
            throw LibreLinkUpError.invalidURL
        }

        let request = buildRequest(url: url, method: "GET", authenticated: true)
        return try await execute(request)
    }

    private func post<T: Encodable>(path: String, body: T, authenticated: Bool) async throws -> Data {
        guard let url = URL(string: path, relativeTo: region.baseURL) else {
            throw LibreLinkUpError.invalidURL
        }

        var request = buildRequest(url: url, method: "POST", authenticated: authenticated)
        request.httpBody = try JSONEncoder().encode(body)
        return try await execute(request)
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LibreLinkUpError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibreLinkUpError.invalidResponse
        }

        // 401 means the JWT expired or was invalidated server-side. SyncService
        // catches this, re-logs in with the stored credentials, and retries once.
        if httpResponse.statusCode == 401 {
            throw LibreLinkUpError.sessionExpired
        }

        // LibreLinkUp uses 429 (and 430) for rate limits and login lockouts, with
        // the wait either in a Retry-After header or a `lockout` field in the body.
        if httpResponse.statusCode == 429 || httpResponse.statusCode == 430 {
            throw LibreLinkUpError.rateLimited(retryAfterSeconds: Self.retryAfterSeconds(httpResponse, body: data))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LibreLinkUpError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    nonisolated private static func retryAfterSeconds(_ response: HTTPURLResponse, body: Data) -> Int? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Int(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        return (try? JSONDecoder().decode(RateLimitResponse.self, from: body))?.data?.lockout
    }
}
