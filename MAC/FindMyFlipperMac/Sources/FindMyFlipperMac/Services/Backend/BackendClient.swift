import Foundation

struct BackendClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: Constants.backendBaseURL)!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - GET /health
    func health() async throws -> HealthResponse {
        try await get("/health")
    }

    // MARK: - POST /keys/validate
    func validateKeys(rawContent: String) async throws -> KeyValidationResponse {
        try await post("/keys/validate", body: KeysValidateRequest(rawContent: rawContent))
    }

    // MARK: - POST /keys/generate
    func generateKeys() async throws -> GenerateKeysResponse {
        try await post("/keys/generate", body: EmptyBody())
    }

    // MARK: - POST /reports/decrypted
    func fetchDecryptedReports(hashedAdvKey: String, privateKeyBase64: String, hours: Int = 24) async throws -> ReportsResponse {
        let req = ReportsRequest(hashedAdvKeyBase64: hashedAdvKey, privateKeyBase64: privateKeyBase64, hours: hours)
        let response: ReportsResponse = try await post("/reports/decrypted", body: req)
        if !response.ok {
            let detail = response.error ?? response.message ?? "The Find My reports service rejected the request."
            if detail.lowercased().contains("auth") || detail.lowercased().contains("sign in") {
                throw BackendError.authRequired
            }
            throw BackendError.server(detail)
        }
        return response
    }

    // MARK: - POST /reports/refresh
    func refreshReports(hashedAdvKey: String, privateKeyBase64: String, hours: Int = 24) async throws -> ReportsResponse {
        let req = ReportsRequest(hashedAdvKeyBase64: hashedAdvKey, privateKeyBase64: privateKeyBase64, hours: hours)
        return try await post("/reports/refresh", body: req)
    }

    // MARK: - GET /reports/latest
    func latestReport(hashedAdvKey: String) async throws -> ReportsResponse {
        let encoded = hashedAdvKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hashedAdvKey
        return try await get("/reports/latest?hashed_adv_key_base64=\(encoded)")
    }

    // MARK: - POST /auth/status
    func authStatus() async throws -> AuthStatusResponse {
        try await post("/auth/status", body: EmptyBody())
    }

    // MARK: - POST /auth/connect
    func connectAuth(
        username: String? = nil,
        password: String? = nil,
        secondFactor: String = "trusted_device",
        code: String? = nil
    ) async throws -> AuthConnectResponse {
        try await post(
            "/auth/connect",
            body: AuthConnectRequest(
                username: username,
                password: password,
                secondFactor: secondFactor,
                code: code
            ),
            timeout: 90
        )
    }

    // MARK: - POST /auth/refresh
    func refreshAuth() async throws -> AuthRefreshResponse {
        try await post("/auth/refresh", body: EmptyBody())
    }

    // MARK: - POST /auth/start-anisette
    func startAnisette(installIfMissing: Bool = true) async throws -> StartAnisetteResponse {
        try await post(
            "/auth/start-anisette",
            body: StartAnisetteRequest(installIfMissing: installIfMissing),
            timeout: 150
        )
    }

    // MARK: - Generic helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, timeout: TimeInterval = 30) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackendError.networkUnavailable
            }
            if http.statusCode == 401 { throw BackendError.authRequired }
            if http.statusCode >= 500 { throw BackendError.httpError(http.statusCode) }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw BackendError.decodingFailed
            }
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.networkUnavailable
        }
    }
}

private struct EmptyBody: Encodable {}
