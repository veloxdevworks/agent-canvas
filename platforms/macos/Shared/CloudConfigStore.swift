import Foundation

/// Persisted cloud API base URL under `~/.velox/canvas/cloud-config.json`.
struct CloudConfigStore: Codable, Equatable {
    var apiBaseURL: String
    /// Default poll interval for new subscriptions (seconds).
    var defaultPollIntervalSeconds: Int
    /// Public OAuth client id (no secret). Prefer env `AGENT_CANVAS_OAUTH_CLIENT_ID`.
    var oauthClientId: String?
    /// Optional issuer override when PRM discovery is unavailable.
    var oauthIssuerOverride: String?

    static let defaultAPIBase = "https://canvas.velox.test"
    static let defaultPoll: Int = 60

    static var fileURL: URL {
        CanvasStorage.applicationSupportRoot
            .appendingPathComponent(AgentCanvasConstants.cloudConfigFileName)
    }

    static func load() -> CloudConfigStore {
        CanvasStorage.ensureDirectories()
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(CloudConfigStore.self, from: data)
        else {
            return CloudConfigStore(
                apiBaseURL: ProcessInfo.processInfo.environment["AGENT_CANVAS_API_URL"]
                    ?? defaultAPIBase,
                defaultPollIntervalSeconds: defaultPoll,
                oauthClientId: nil,
                oauthIssuerOverride: nil
            )
        }
        return decoded
    }

    func save() throws {
        CanvasStorage.ensureDirectories()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
    }

    var normalizedAPIBase: String {
        apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Canvas origin used as OAuth `resource` / audience (scheme + host, no path).
    var resourceOrigin: String {
        guard let url = URL(string: normalizedAPIBase),
              let scheme = url.scheme,
              let host = url.host
        else {
            return normalizedAPIBase
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Resolved public client id: env wins, then persisted config.
    var resolvedOAuthClientId: String? {
        if let env = ProcessInfo.processInfo.environment[AgentCanvasConstants.oauthClientIdEnvName]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty
        {
            return env
        }
        if let id = oauthClientId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return nil
    }

    func canvasesCollectionURL() -> URL? {
        URL(string: normalizedAPIBase + "/api/v1/canvases")
    }

    func canvasURL(slug: String) -> URL? {
        URL(string: normalizedAPIBase + "/api/v1/canvases/\(slug)")
    }

    func publicViewerURL(slug: String) -> URL? {
        URL(string: normalizedAPIBase + "/c/\(slug)")
    }
}
