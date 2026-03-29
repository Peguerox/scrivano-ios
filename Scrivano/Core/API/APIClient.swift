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
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIClientError.invalidURL
        }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIClientError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw APIClientError.unauthorized
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Try to decode as an error message
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(apiErr.message)
            }
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

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        req.setValue(String(durationSeconds), forHTTPHeaderField: "audio_duration_seconds")
        req.setValue(filename, forHTTPHeaderField: "audio_filename")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = audioData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIClientError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw APIClientError.unauthorized
        }

        do {
            return try JSONDecoder().decode(TranscribeResponse.self, from: data)
        } catch {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(apiErr.message)
            }
            throw APIClientError.decodingError(error)
        }
    }

    // MARK: - Poll task result
    func pollResult(taskId: String, endpoint: String = "/api/audio/result") async throws -> TaskResult {
        struct Body: Encodable { let taskId: String; enum CodingKeys: String, CodingKey { case taskId = "task_id" } }
        return try await request(
            path: endpoint,
            method: "POST",
            body: Body(taskId: taskId),
            responseType: TaskResult.self
        )
    }
}

// MARK: - Encodable helpers
struct EmptyBody: Encodable {}
