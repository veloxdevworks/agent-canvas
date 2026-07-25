import Foundation

/// Persisted cloud API base URL under `~/.velox/canvas/cloud-config.json`.
struct CloudConfigStore: Codable, Equatable {
    var apiBaseURL: String
    /// Default poll interval for new subscriptions (seconds).
    var defaultPollIntervalSeconds: Int

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
                defaultPollIntervalSeconds: defaultPoll
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
