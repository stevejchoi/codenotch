import Foundation

enum OllamaUsage {
    private struct Response: Decodable {
        struct Model: Decodable {
            let name: String
            let size: Int64?
            let size_vram: Int64?
            let context_length: Int?
        }
        let models: [Model]
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> LocalRuntimeReading {
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            var seen = Set<String>()
            let models = try response.models.map { model in
                guard !model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      seen.insert(model.name).inserted,
                      model.size.map({ $0 >= 0 }) ?? true,
                      model.size_vram.map({ $0 >= 0 }) ?? true,
                      model.context_length.map({ $0 > 0 }) ?? true else {
                    throw OllamaError.invalidResponse
                }
                return LocalRuntimeReading.Model(
                    id: model.name, name: model.name, memoryBytes: model.size,
                    gpuMemoryBytes: model.size_vram, contextLength: model.context_length
                )
            }.sorted { $0.id < $1.id }
            return LocalRuntimeReading(models: models, observedAt: now)
        } catch {
            throw OllamaError.invalidResponse
        }
    }
}

enum OllamaError: LocalizedError {
    case invalidEndpoint
    case unavailable
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Use an HTTP address on this Mac, such as http://127.0.0.1:11434."
        case .unavailable:
            return "Ollama server unavailable. Open Ollama and check the server address."
        case .invalidResponse:
            return "This server did not return an Ollama model listing."
        case .http(let code):
            return "Ollama returned HTTP \(code). Check the server address and configuration."
        }
    }
}

enum OllamaEndpoint {
    static let defaultAddress = "http://127.0.0.1:11434"

    static func parse(_ address: String) throws -> URL {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "http",
              let host = parts.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw OllamaError.invalidEndpoint
        }
        // Resolve the familiar spelling to a literal loopback address; no DNS or
        // proxy is needed for the local-only connection.
        parts.host = host == "localhost" ? "127.0.0.1" : host
        parts.scheme = "http"
        parts.path = ""
        guard let url = parts.url else { throw OllamaError.invalidEndpoint }
        return url
    }
}
