import CryptoKit
import Foundation

enum LibreLinkUpError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed(String)
    case termsOfUseRequired
    case networkError(Error)
    case decodingError(Error)
    case noData
    case regionRedirect(LibreLinkUpRegion)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .termsOfUseRequired:
            return "You must accept the Terms of Use in the LibreLinkUp app before continuing."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .noData:
            return "No data returned from server."
        case .regionRedirect(let region):
            return "Redirecting to \(region.displayName) server."
        }
    }
}

protocol GlucoseDataProvider: Sendable {
    func fetchConnections() async throws -> [Connection]
    func fetchGraphData(connectionId: String) async throws -> GraphData
}

actor LibreLinkUpService: GlucoseDataProvider {
    private let keychain = KeychainService()
    private let session: URLSession

    private var region: LibreLinkUpRegion
    private var token: String?
    private var userId: String?

    private static let apiHeaders: [String: String] = [
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

        // Check for regional redirect
        if let loginData = response.data, loginData.redirect == true,
           let regionString = loginData.region {
            if let redirectRegion = LibreLinkUpRegion.allCases.first(where: {
                $0.rawValue.contains(regionString.lowercased())
            }) {
                // Retry login with the correct regional server
                return try await login(email: email, password: password, region: redirectRegion)
            }
        }

        // Also check top-level redirect
        if response.redirect == true, let regionString = response.region {
            if let redirectRegion = LibreLinkUpRegion.allCases.first(where: {
                $0.rawValue.contains(regionString.lowercased())
            }) {
                return try await login(email: email, password: password, region: redirectRegion)
            }
        }

        guard response.status == 0 || response.status == 2 else {
            throw LibreLinkUpError.authenticationFailed("Status: \(response.status)")
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

        // Handle 401 — token may be expired, try re-login once
        if httpResponse.statusCode == 401 {
            throw LibreLinkUpError.authenticationFailed("Token expired (HTTP 401).")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LibreLinkUpError.invalidResponse
        }

        return data
    }
}
