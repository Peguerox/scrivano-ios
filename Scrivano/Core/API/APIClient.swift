import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(String)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL."
        case .noData:              return "No data received."
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .serverError(let m):  return m
        case .unauthorized:        return "Session expired. Please log in again."
        case .networkError(let e): return e.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    let baseURL = "https://app.scrivano.net"
    private let session = URLSession.shared

    private init() {}

    // MARK: - Token management
    var authToken: String? {
        get { KeychainService.shared.getToken() }
    }

    // MARK: - Core request
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIClientError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        if let body = body { req.httpBody = try JSONEncoder().encode(body) }
        return try await execute(req, responseType: responseType, rebuildOn401: {
            if let token = self.authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            return req
        })
    }

    /// Sends the request; on 401 refreshes token once and retries.
    private func execute<T: Decodable>(_ req: URLRequest, responseType: T.Type, rebuildOn401: (() -> URLRequest)? = nil) async throws -> T {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) } catch { throw APIClientError.networkError(error) }

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let rebuild = rebuildOn401 {
                appLog("  401 — auto-refreshing token", level: .warning)
                do { try await refreshToken() } catch {
                    // Network errors mean refresh may succeed when connectivity returns —
                    // propagate as-is so poll loops treat it as a transient blip, not a logout.
                    if let apiErr = error as? APIClientError, case .networkError = apiErr { throw apiErr }
                    // Surface the server's actual error message from the 401 body if present
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = json["message"] as? String {
                        throw APIClientError.serverError(message)
                    }
                    throw APIClientError.unauthorized
                }
                appLog("  Token refreshed — retrying", level: .success)
                var req2 = rebuild()
                if let token = authToken { req2.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let (data2, _): (Data, URLResponse)
                do { (data2, _) = try await session.data(for: req2) } catch { throw APIClientError.networkError(error) }
                return try decode(data2, as: responseType)
            }
            throw APIClientError.unauthorized
        }
        return try decode(data, as: responseType)
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw APIClientError.serverError(apiErr.message) }
            throw APIClientError.decodingError(error)
        }
    }

    // MARK: - Multipart / raw audio upload
    func uploadAudio(
        data audioData: Data,
        filename: String,
        durationSeconds: Double,
        extraHeaders: [String: String] = [:]
    ) async throws -> TranscribeResponse {
        guard let url = URL(string: baseURL + "/api/audio/transcribe") else {
            throw APIClientError.invalidURL
        }

        var req = URLRequest(url: url, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        req.setValue(String(durationSeconds), forHTTPHeaderField: "audio_duration_seconds")
        req.setValue(filename, forHTTPHeaderField: "audio_filename")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            appLog("  auth token: present (\(token.prefix(12))…)")
        } else {
            appLog("  auth token: MISSING", level: .error)
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = audioData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            appLog("  uploadAudio network error: \(error.localizedDescription)", level: .error)
            throw APIClientError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            appLog("  uploadAudio HTTP \(http.statusCode)")
            switch http.statusCode {
            case 200...299:
                break
            case 401:
                appLog("  401 — auto-refreshing token for upload", level: .warning)
                do { try await refreshToken() } catch { throw APIClientError.unauthorized }
                appLog("  Token refreshed — retrying upload", level: .success)
                if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let (data2, _): (Data, URLResponse)
                do { (data2, _) = try await session.data(for: req) } catch { throw APIClientError.networkError(error) }
                appLog("  uploadAudio retry — decoding response")
                return try decode(data2, as: TranscribeResponse.self)
            case 413:
                throw APIClientError.serverError("Audio file is too large. Try a shorter recording.")
            default:
                throw APIClientError.serverError("Server error (\(http.statusCode)).")
            }
        }
        appLog("  uploadAudio — decoding response")
        return try decode(data, as: TranscribeResponse.self)
    }

    // MARK: - Poll audio task result
    // GET /api/audio/result/:taskId
    func pollAudioResult(taskId: String) async throws -> AudioTaskResult {
        return try await request(
            path: "/api/audio/result/\(taskId)",
            method: "GET",
            responseType: AudioTaskResult.self
        )
    }

    // MARK: - Poll notes task result
    // GET /api/notes/result/:taskId
    func pollNoteResult(taskId: String) async throws -> NoteTaskResult {
        return try await request(
            path: "/api/notes/result/\(taskId)",
            method: "GET",
            responseType: NoteTaskResult.self
        )
    }

    // MARK: - Poll image task result
    // GET /api/image/result/:taskId
    func pollImageResult(taskId: String) async throws -> ImageTaskResult {
        return try await request(
            path: "/api/image/result/\(taskId)",
            method: "GET",
            responseType: ImageTaskResult.self
        )
    }

    // MARK: - Refresh token
    // ⚠️ Must call execute() with rebuildOn401: nil — otherwise a 401 from the
    // refresh endpoint would call refreshToken() again → infinite recursion.
    func refreshToken() async throws {
        guard let refresh = KeychainService.shared.getRefreshToken() else {
            appLog("  refreshToken: no refresh token in keychain — forcing logout", level: .error)
            Task { @MainActor in AuthManager.shared.forceLogout() }
            throw APIClientError.unauthorized
        }
        struct Body: Encodable {
            let refreshToken: String
            enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
        }
        struct Res: Decodable {
            let success: Bool; let token: String?; let refreshToken: String?
            enum CodingKeys: String, CodingKey { case success, token; case refreshToken = "refresh_token" }
        }
        guard let url = URL(string: baseURL + "/api/auth/refresh") else { throw APIClientError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(Body(refreshToken: refresh))

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIClientError.networkError(error) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        appLog("  refreshToken: HTTP \(status)", level: status == 200 ? .info : .error)

        // Backend refresh failed — try silent Google reauth as fallback, else force logout
        if status != 200 {
            let provider = KeychainService.shared.getLoginProvider()
            if provider == "google" {
                appLog("  refreshToken: backend refresh failed — trying silent Google reauth", level: .warning)
                do {
                    try await SocialAuthManager.shared.silentGoogleReauth()
                    appLog("  refreshToken: silent Google reauth succeeded", level: .success)
                    return
                } catch let urlErr as URLError
                        where urlErr.code == .networkConnectionLost
                           || urlErr.code == .notConnectedToInternet
                           || urlErr.code == .timedOut
                           || urlErr.code == .cannotConnectToHost {
                    // Network was unavailable — don't force logout. The session may recover
                    // when connectivity returns; the next API call will retry the full refresh.
                    appLog("  refreshToken: silent Google reauth failed (network unavailable) — not logging out", level: .warning)
                    throw APIClientError.networkError(urlErr)
                } catch {
                    appLog("  refreshToken: silent Google reauth failed — \(error.localizedDescription)", level: .error)
                }
            }
            // All refresh options exhausted — force logout so user gets a clean login screen
            appLog("  refreshToken: all attempts failed — forcing logout", level: .error)
            Task { @MainActor in AuthManager.shared.forceLogout() }
            throw APIClientError.unauthorized
        }

        guard let res = try? JSONDecoder().decode(Res.self, from: data), let token = res.token else {
            appLog("  refreshToken: decode failed or token missing — forcing logout", level: .error)
            Task { @MainActor in AuthManager.shared.forceLogout() }
            throw APIClientError.unauthorized
        }
        KeychainService.shared.saveToken(token)
        if let r = res.refreshToken { KeychainService.shared.saveRefreshToken(r) }
        appLog("  refreshToken: new token saved (\(token.prefix(12))…)", level: .success)
    }

    // MARK: - OpenAI Key
    struct OpenAIKeyStatus: Decodable { let hasKey: Bool; let key: String? }

    func getOpenAIKeyStatus() async throws -> OpenAIKeyStatus {
        return try await request(path: "/api/user/openai-key", responseType: OpenAIKeyStatus.self)
    }

    func saveOpenAIKey(_ key: String) async throws {
        struct Body: Encodable { let key: String }
        struct Res: Decodable { let success: Bool }
        let _ = try await request(path: "/api/user/openai-key", method: "POST", body: Body(key: key), responseType: Res.self)
    }

    func deleteOpenAIKey() async throws {
        struct Res: Decodable { let success: Bool }
        let _ = try await request(path: "/api/user/openai-key", method: "DELETE", responseType: Res.self)
    }

    // MARK: - Cancel tasks
    // DELETE /api/audio/cancel/:taskId
    func cancelAudioTask(taskId: String) async throws {
        struct Res: Decodable { let success: Bool }
        let _ = try await request(path: "/api/audio/cancel/\(taskId)", method: "DELETE", responseType: Res.self)
    }

    // DELETE /api/notes/cancel/:taskId
    func cancelNoteTask(taskId: String) async throws {
        struct Res: Decodable { let success: Bool }
        let _ = try await request(path: "/api/notes/cancel/\(taskId)", method: "DELETE", responseType: Res.self)
    }

    // DELETE /api/image/cancel/:taskId
    func cancelImageTask(taskId: String) async throws {
        struct Res: Decodable { let success: Bool }
        let _ = try await request(path: "/api/image/cancel/\(taskId)", method: "DELETE", responseType: Res.self)
    }

    // MARK: - Save note
    // POST /api/notes/save
    // Body: { text, itemId, promptLabel? }
    func saveNote(text: String, itemId: String, promptLabel: String?) async throws {
        struct Body: Encodable {
            let text: String
            let itemId: String
            let promptLabel: String?
            enum CodingKeys: String, CodingKey {
                case text
                case itemId = "itemId"
                case promptLabel = "promptLabel"
            }
        }
        struct Res: Decodable { let success: Bool; let message: String? }
        let res = try await request(
            path: "/api/notes/save",
            method: "POST",
            body: Body(text: text, itemId: itemId, promptLabel: promptLabel),
            responseType: Res.self
        )
        if !res.success { throw APIClientError.serverError(res.message ?? "Failed to save note.") }
    }

    // MARK: - Upload document (multipart)
    // POST /api/import/extract — multipart FormData with `file` field
    func uploadDocument(fileURL: URL) async throws -> String {
        guard let url = URL(string: baseURL + "/api/import/extract") else {
            throw APIClientError.invalidURL
        }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeTypeFor(pathExtension: fileURL.pathExtension)

        var body = Data()
        let nl = "\r\n"
        body.append("--\(boundary)\(nl)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(nl)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(nl)\(nl)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(nl)--\(boundary)--\(nl)".data(using: .utf8)!)
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIClientError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw APIClientError.unauthorized
        }

        struct Res: Decodable { let success: Bool; let text: String?; let message: String? }
        do {
            let res = try JSONDecoder().decode(Res.self, from: data)
            if res.success, let text = res.text { return text }
            throw APIClientError.serverError(res.message ?? "Failed to extract document.")
        } catch let err as APIClientError {
            throw err
        } catch {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(apiErr.message)
            }
            throw APIClientError.decodingError(error)
        }
    }

    private func mimeTypeFor(pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "txt":  return "text/plain"
        default:     return "application/octet-stream"
        }
    }

    // MARK: - Submit collection
    // POST /api/collections/upload
    func submitCollection(payload: CollectionUploadPayload) async throws {
        struct Body: Encodable { let data: CollectionUploadPayload }
        struct Res: Decodable { let success: Bool; let message: String? }
        let res = try await request(
            path: "/api/collections/upload",
            method: "POST",
            body: Body(data: payload),
            responseType: Res.self
        )
        if !res.success { throw APIClientError.serverError(res.message ?? "Failed to submit collection.") }
    }

    // MARK: - Save transcript
    // POST /api/audio/save-transcript
    // Body: { text, itemName, collectionName, durationSeconds? }
    func saveTranscript(text: String, itemName: String, collectionName: String, durationSeconds: Double?) async throws {
        struct Body: Encodable {
            let text: String
            let itemName: String
            let collectionName: String
            let durationSeconds: Double?
            enum CodingKeys: String, CodingKey {
                case text
                case itemName = "itemName"
                case collectionName = "collectionName"
                case durationSeconds = "durationSeconds"
            }
        }
        struct Res: Decodable { let success: Bool; let message: String? }
        let res = try await request(
            path: "/api/audio/save-transcript",
            method: "POST",
            body: Body(text: text, itemName: itemName, collectionName: collectionName, durationSeconds: durationSeconds),
            responseType: Res.self
        )
        if !res.success { throw APIClientError.serverError(res.message ?? "Failed to save transcript.") }
    }
}

// MARK: - Encodable helpers
struct EmptyBody: Encodable {}
