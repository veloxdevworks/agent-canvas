import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

/// Velox OAuth 2.1 authorization code + PKCE S256 (public client).
/// Gated by `CloudFeature`. No session cookies on token/API traffic.
@MainActor
final class VeloxOAuthSession: NSObject, ObservableObject {
    static let shared = VeloxOAuthSession()

    @Published private(set) var isSignedIn = false
    @Published private(set) var accountLabel: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    private var pending: PendingAuth?
    private var cachedMetadata: (issuer: String, authorization: URL, token: URL, revoke: URL?)?
    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    /// Ephemeral session: never send or store cookies.
    private lazy var http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private struct PendingAuth {
        var state: String
        var codeVerifier: String
        var clientId: String
        var resource: String
        var tokenEndpoint: URL
        var continuation: CheckedContinuation<Void, Error>?
    }

    enum OAuthError: LocalizedError {
        case featureDisabled
        case discovery(String)
        case badURL
        case stateMismatch
        case cancelled
        case token(String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .featureDisabled:
                return "Cloud features disabled — enable debug cloud first."
            case let .discovery(m): return "OAuth discovery: \(m)"
            case .badURL: return "Invalid OAuth URL."
            case .stateMismatch: return "OAuth state mismatch — try signing in again."
            case .cancelled: return "Sign-in cancelled."
            case let .token(m): return m
            case .notSignedIn: return "Not signed in."
            }
        }
    }

    private override init() {
        super.init()
        refreshPublishedState()
    }

    func refreshPublishedState() {
        isSignedIn = OAuthKeychain.hasRefreshToken || OAuthKeychain.hasAccessToken
        expiresAt = OAuthKeychain.expiresAt
        accountLabel = Self.emailFromIdToken(OAuthKeychain.get(.idToken))
            ?? (isSignedIn ? "Signed in" : nil)
    }

    // MARK: - Sign in / out

    func signIn(config: CloudConfigStore = .load(), presentingWindow: NSWindow? = nil) async throws {
        guard CloudFeature.isEnabled else { throw OAuthError.featureDisabled }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let clientId = AgentCanvasConstants.oauthClientId
        let resource = config.resourceOrigin
        let meta = try await discover(resource: resource, config: config)

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallengeS256(verifier: verifier)
        let state = Self.randomURLSafe(bytes: 16)

        var components = URLComponents(url: meta.authorization, resolvingAgainstBaseURL: false)!
        // Better Auth rejects RFC 8707 `resource` on authorize — send it on token/refresh only.
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: AgentCanvasConstants.oauthRedirectURI),
            URLQueryItem(name: "scope", value: AgentCanvasConstants.oauthScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components.url else { throw OAuthError.badURL }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pending = PendingAuth(
                state: state,
                codeVerifier: verifier,
                clientId: clientId,
                resource: resource,
                tokenEndpoint: meta.token,
                continuation: cont
            )
            startWebAuth(url: authURL, presentingWindow: presentingWindow)
        }
        refreshPublishedState()
    }

    func signOut(config: CloudConfigStore = .load()) async {
        if let refresh = OAuthKeychain.get(.refreshToken),
           let resource = OAuthKeychain.get(.resource) ?? Optional(config.resourceOrigin),
           let meta = try? await discover(resource: resource, config: config),
           let revoke = meta.revoke
        {
            let clientId = OAuthKeychain.get(.clientId) ?? AgentCanvasConstants.oauthClientId
            var req = URLRequest(url: revoke)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.formBody([
                "token": refresh,
                "token_type_hint": "refresh_token",
                "client_id": clientId,
            ])
            _ = try? await http.data(for: req)
        }
        OAuthKeychain.clearAll()
        cachedMetadata = nil
        pending = nil
        lastError = nil
        refreshPublishedState()
    }

    /// Returns a valid access token, refreshing if needed. Nil if signed out.
    func validAccessToken(config: CloudConfigStore = .load()) async throws -> String? {
        guard CloudFeature.isEnabled else { return nil }
        guard OAuthKeychain.hasAccessToken || OAuthKeychain.hasRefreshToken else { return nil }

        if let exp = OAuthKeychain.expiresAt, exp.timeIntervalSinceNow > 60,
           let access = OAuthKeychain.get(.accessToken), !access.isEmpty
        {
            return access
        }
        try await refresh(config: config)
        return OAuthKeychain.get(.accessToken)
    }

    // MARK: - Callback

    /// Handle `agentcanvas://oauth/callback?code=…&state=…` (URL handler or ASWeb).
    func handleCallbackURL(_ url: URL) {
        Task { @MainActor in
            do {
                try await completeCallback(url)
            } catch {
                lastError = error.localizedDescription
                if let cont = pending?.continuation {
                    pending?.continuation = nil
                    cont.resume(throwing: error)
                }
                pending = nil
            }
        }
    }

    private func completeCallback(_ url: URL) async throws {
        guard let pending else {
            throw OAuthError.token("No pending sign-in.")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OAuthError.badURL
        }
        let items = components.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        if let err = q("error") {
            let desc = q("error_description") ?? err
            throw OAuthError.token(desc.replacingOccurrences(of: "+", with: " "))
        }
        guard let state = q("state"), state == pending.state else {
            throw OAuthError.stateMismatch
        }
        guard let code = q("code"), !code.isEmpty else {
            throw OAuthError.token("Missing authorization code.")
        }

        try await exchangeCode(
            code: code,
            verifier: pending.codeVerifier,
            clientId: pending.clientId,
            resource: pending.resource,
            tokenEndpoint: pending.tokenEndpoint
        )

        let cont = pending.continuation
        self.pending = nil
        cont?.resume()
        refreshPublishedState()
    }

    // MARK: - Discovery

    struct ASMetadata {
        var issuer: String
        var authorization: URL
        var token: URL
        var revoke: URL?
    }

    func discover(resource: String, config: CloudConfigStore) async throws -> ASMetadata {
        if let cached = cachedMetadata {
            return ASMetadata(
                issuer: cached.issuer,
                authorization: cached.authorization,
                token: cached.token,
                revoke: cached.revoke
            )
        }

        let issuer: String
        if let override = config.oauthIssuerOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            issuer = override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if let discovered = try? await fetchProtectedResourceIssuer(resource: resource) {
            issuer = discovered
        } else if let fallback = Self.fallbackIssuer(forResource: resource) {
            issuer = fallback
        } else {
            throw OAuthError.discovery("Could not resolve authorization server for \(resource)")
        }

        let meta = try await fetchAuthorizationServerMetadata(issuer: issuer)
        cachedMetadata = (issuer, meta.authorization, meta.token, meta.revoke)
        return meta
    }

    private func fetchProtectedResourceIssuer(resource: String) async throws -> String {
        let base = resource.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/.well-known/oauth-protected-resource") else {
            throw OAuthError.badURL
        }
        let (data, response) = try await http.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw OAuthError.discovery("PRM HTTP \(code)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.discovery("Invalid PRM JSON")
        }
        if let arr = obj["authorization_servers"] as? [String], let first = arr.first, !first.isEmpty {
            return first.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        throw OAuthError.discovery("No authorization_servers in PRM")
    }

    private func fetchAuthorizationServerMetadata(issuer: String) async throws -> ASMetadata {
        let base = issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/.well-known/oauth-authorization-server") else {
            throw OAuthError.badURL
        }
        let (data, response) = try await http.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw OAuthError.discovery("AS metadata HTTP \(code)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = obj["authorization_endpoint"] as? String,
              let token = obj["token_endpoint"] as? String,
              let authURL = URL(string: auth),
              let tokenURL = URL(string: token)
        else {
            throw OAuthError.discovery("Missing authorization_endpoint / token_endpoint")
        }
        let revoke = (obj["revocation_endpoint"] as? String).flatMap(URL.init(string:))
        return ASMetadata(issuer: base, authorization: authURL, token: tokenURL, revoke: revoke)
    }

    private static func fallbackIssuer(forResource resource: String) -> String? {
        guard let host = URL(string: resource)?.host?.lowercased() else { return nil }
        switch host {
        case "canvas.velox.test":
            return "https://auth.velox.test"
        case "canvas.veloxdevworks.com":
            return "https://auth.veloxdevworks.com"
        default:
            return nil
        }
    }

    // MARK: - Token

    private func exchangeCode(
        code: String,
        verifier: String,
        clientId: String,
        resource: String,
        tokenEndpoint: URL
    ) async throws {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": AgentCanvasConstants.oauthRedirectURI,
            "resource": resource,
        ])
        try await applyTokenResponse(request: req, clientId: clientId, resource: resource)
    }

    private func refresh(config: CloudConfigStore) async throws {
        guard let refreshToken = OAuthKeychain.get(.refreshToken), !refreshToken.isEmpty else {
            OAuthKeychain.clearAll()
            refreshPublishedState()
            throw OAuthError.notSignedIn
        }
        let clientId = OAuthKeychain.get(.clientId) ?? AgentCanvasConstants.oauthClientId
        let resource = OAuthKeychain.get(.resource) ?? config.resourceOrigin
        let meta = try await discover(resource: resource, config: config)

        var req = URLRequest(url: meta.token)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken,
            "resource": resource,
        ])
        do {
            try await applyTokenResponse(request: req, clientId: clientId, resource: resource)
            refreshPublishedState()
        } catch {
            OAuthKeychain.clearAll()
            refreshPublishedState()
            throw error
        }
    }

    private func applyTokenResponse(request: URLRequest, clientId: String, resource: String) async throws {
        let (data, response) = try await http.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(code) else {
            throw OAuthError.token("Token HTTP \(code): \(text.prefix(200))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String
        else {
            throw OAuthError.token("Token response missing access_token")
        }
        let refresh = obj["refresh_token"] as? String
        let expiresIn: TimeInterval?
        if let n = obj["expires_in"] as? Double {
            expiresIn = n
        } else if let n = obj["expires_in"] as? Int {
            expiresIn = TimeInterval(n)
        } else {
            expiresIn = 600
        }
        let idToken = obj["id_token"] as? String
        OAuthKeychain.saveTokens(
            accessToken: access,
            refreshToken: refresh ?? OAuthKeychain.get(.refreshToken),
            expiresIn: expiresIn,
            clientId: clientId,
            resource: resource,
            idToken: idToken
        )
    }

    // MARK: - Browser

    private func startWebAuth(url: URL, presentingWindow: NSWindow?) {
        presentationAnchor = presentingWindow ?? NSApp.keyWindow ?? NSApp.windows.first
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: AgentCanvasConstants.oauthURLScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    {
                        self.failPending(OAuthError.cancelled)
                    } else {
                        self.failPending(error)
                    }
                    return
                }
                guard let callbackURL else {
                    self.failPending(OAuthError.cancelled)
                    return
                }
                do {
                    try await self.completeCallback(callbackURL)
                } catch {
                    self.failPending(error)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() {
            // Fallback: open system browser; rely on URL scheme handler.
            NSWorkspace.shared.open(url)
        }
    }

    private func failPending(_ error: Error) {
        lastError = error.localizedDescription
        if let cont = pending?.continuation {
            pending?.continuation = nil
            cont.resume(throwing: error)
        }
        pending = nil
        refreshPublishedState()
    }

    // MARK: - Crypto helpers

    static func makeCodeVerifier() -> String {
        randomURLSafe(bytes: 32)
    }

    static func codeChallengeS256(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func randomURLSafe(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    static func emailFromIdToken(_ idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (obj["email"] as? String) ?? (obj["preferred_username"] as? String)
    }

    static func isOAuthCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == AgentCanvasConstants.oauthURLScheme else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        // agentcanvas://oauth/callback
        if host == AgentCanvasConstants.oauthCallbackHost {
            return path == AgentCanvasConstants.oauthCallbackPath || path.isEmpty || path == "/"
        }
        return path.hasPrefix("/oauth/callback") || path == "/oauth/callback"
    }
}

extension VeloxOAuthSession: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchor ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
                ?? ASPresentationAnchor()
        }
    }
}
