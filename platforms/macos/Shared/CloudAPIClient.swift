import Foundation

/// Minimal HTTP client for canvas cloud (publish + fetch). Gated by `CloudFeature`.
enum CloudAPIClient {
    struct PublishResult: Equatable {
        var slug: String
        var publicURL: String
        var apiURL: String
        var editToken: String?
        var version: UInt32?
        var etag: String?
    }

    enum APIError: LocalizedError {
        case featureDisabled
        case badURL
        case http(Int, String)
        case decode
        case emptyCanvas
        case missingToken
        case message(String)

        var errorDescription: String? {
            switch self {
            case .featureDisabled: return "Cloud features disabled (debug + AGENT_CANVAS_CLOUD_PUBLISH)."
            case .badURL: return "Invalid API base URL."
            case let .http(code, body): return "HTTP \(code): \(body)"
            case .decode: return "Could not parse server response."
            case .emptyCanvas: return "Canvas has no content to publish."
            case .missingToken: return "No edit token in Keychain — publish first or paste a token."
            case let .message(m): return m
            }
        }
    }

    static func publish(
        address: CanvasAddress,
        slug: String?,
        config: CloudConfigStore = .load()
    ) async throws -> PublishResult {
        try requireFeature()
        let doc = CanvasStorage.load(address: address)
        if doc.isEmptyContent { throw APIError.emptyCanvas }

        guard let url = config.canvasesCollectionURL() else { throw APIError.badURL }

        var body: [String: Any] = [
            "document": try jsonObject(from: doc),
        ]
        if let slug, !slug.isEmpty {
            body["slug"] = slug
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        request.setValue("agent-canvas-host/\(ver)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(code) else {
            throw APIError.http(code, String(text.prefix(400)))
        }

        let result = try parsePublishResponse(data: data, config: config, fallbackSlug: slug)
        if let token = result.editToken {
            _ = CloudKeychain.setToken(token, slug: result.slug)
        }
        try CloudShareIndex.upsert(
            CloudShareRecord(
                canvas: address.rawValue,
                slug: result.slug,
                publicUrl: result.publicURL,
                apiUrl: result.apiURL,
                sharedAt: Date(),
                lastVersion: result.version,
                lastEtag: result.etag
            )
        )
        return result
    }

    static func updateShared(
        address: CanvasAddress,
        editToken: String? = nil,
        config: CloudConfigStore = .load()
    ) async throws -> PublishResult {
        try requireFeature()
        guard let record = CloudShareIndex.record(forCanvas: address.rawValue) else {
            throw APIError.message("Not shared yet — publish first.")
        }
        let token = editToken ?? CloudKeychain.getToken(slug: record.slug)
        guard let token, !token.isEmpty else { throw APIError.missingToken }

        let doc = CanvasStorage.load(address: address)
        if doc.isEmptyContent { throw APIError.emptyCanvas }
        guard let url = URL(string: record.apiUrl) ?? config.canvasURL(slug: record.slug) else {
            throw APIError.badURL
        }

        let body: [String: Any] = ["document": try jsonObject(from: doc)]
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Canvas-Edit-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(code) else {
            throw APIError.http(code, String(text.prefix(400)))
        }

        let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        var version = record.lastVersion
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = obj["currentVersion"] as? Int { version = UInt32(v) }
            else if let v = obj["version"] as? Int { version = UInt32(v) }
        }
        try CloudShareIndex.upsert(
            CloudShareRecord(
                canvas: record.canvas,
                slug: record.slug,
                publicUrl: record.publicUrl,
                apiUrl: record.apiUrl,
                sharedAt: record.sharedAt,
                lastVersion: version,
                lastEtag: etag ?? record.lastEtag
            )
        )
        return PublishResult(
            slug: record.slug,
            publicURL: record.publicUrl,
            apiURL: record.apiUrl,
            editToken: nil,
            version: version,
            etag: etag
        )
    }

    static func unshare(
        slugOrCanvas: String,
        editToken: String? = nil,
        config: CloudConfigStore = .load()
    ) async throws {
        try requireFeature()
        let record = CloudShareIndex.record(forSlug: slugOrCanvas)
            ?? CloudShareIndex.record(forCanvas: slugOrCanvas)
        guard let record else {
            throw APIError.message("No local share for \(slugOrCanvas).")
        }
        let token = editToken ?? CloudKeychain.getToken(slug: record.slug)
        guard let token, !token.isEmpty else { throw APIError.missingToken }
        guard let url = URL(string: record.apiUrl) ?? config.canvasURL(slug: record.slug) else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "X-Canvas-Edit-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) && code != 404 && code != 410 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(code, String(text.prefix(400)))
        }
        _ = CloudKeychain.deleteToken(slug: record.slug)
        try CloudShareIndex.remove(slug: record.slug)
    }

    /// GET subscription URL → write into local canvas slot (one-shot; poller later).
    static func fetchSubscription(_ sub: CloudSubscription) async throws {
        try requireFeature()
        guard let address = CanvasAddress(rawValue: sub.canvas) else {
            throw APIError.message("Invalid canvas id \(sub.canvas)")
        }
        guard let url = URL(string: sub.url) else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let etag = sub.etag, !etag.isEmpty {
            request.setValue("\"\(etag)\"", forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0

        var updated = sub
        updated.lastFetchAt = Date()
        updated.lastStatusCode = code

        if code == 304 {
            updated.lastError = nil
            try CloudSubscriptionStore.upsert(updated)
            return
        }
        if code == 410 {
            updated.lastError = "Gone (unpublished)"
            try CloudSubscriptionStore.upsert(updated)
            throw APIError.http(410, "Canvas unpublished")
        }
        guard (200...299).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            updated.lastError = "HTTP \(code)"
            try CloudSubscriptionStore.upsert(updated)
            throw APIError.http(code, String(text.prefix(400)))
        }

        let doc = try JSONDecoder.canvas.decode(CanvasDocument.self, from: data)
        try CanvasStorage.write(doc, address: address)
        CanvasStorage.reload(address: address)

        let etag = http?.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        updated.etag = etag
        updated.lastError = nil
        try CloudSubscriptionStore.upsert(updated)
    }

    // MARK: - Helpers

    private static func requireFeature() throws {
        guard CloudFeature.isEnabled else { throw APIError.featureDisabled }
    }

    private static func jsonObject(from doc: CanvasDocument) throws -> Any {
        let data = try JSONEncoder.canvas.encode(doc)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func parsePublishResponse(
        data: Data,
        config: CloudConfigStore,
        fallbackSlug: String?
    ) throws -> PublishResult {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode
        }
        let slug = (obj["slug"] as? String)
            ?? fallbackSlug
            ?? ""
        guard !slug.isEmpty else { throw APIError.decode }

        let editToken = (obj["editToken"] as? String)
            ?? (obj["edit_token"] as? String)
            ?? (obj["token"] as? String)

        var publicURL = (obj["publicUrl"] as? String) ?? (obj["public_url"] as? String) ?? ""
        if publicURL.isEmpty, let rel = obj["url"] as? String {
            if rel.hasPrefix("http") {
                publicURL = rel
            } else {
                publicURL = config.normalizedAPIBase + (rel.hasPrefix("/") ? rel : "/\(rel)")
            }
        }
        if publicURL.isEmpty {
            publicURL = config.publicViewerURL(slug: slug)?.absoluteString ?? ""
        }

        var apiURL = (obj["apiUrl"] as? String) ?? (obj["api_url"] as? String) ?? ""
        if apiURL.isEmpty {
            apiURL = config.canvasURL(slug: slug)?.absoluteString ?? ""
        }

        var version: UInt32?
        if let v = obj["currentVersion"] as? Int { version = UInt32(v) }
        else if let v = obj["version"] as? Int { version = UInt32(v) }

        let etag = obj["contentHash"] as? String ?? obj["etag"] as? String

        return PublishResult(
            slug: slug,
            publicURL: publicURL,
            apiURL: apiURL,
            editToken: editToken,
            version: version,
            etag: etag
        )
    }
}

private extension JSONEncoder {
    static let canvas: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let canvas: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

