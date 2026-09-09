// store info from ollama

import Foundation

struct LocalRuntimeReading: Equatable {
    struct Model: Identifiable, Equatable {
        let name: String
        let memoryBytes: Int64?
        let contextLength: Int?
        let quantizationLevel: String?

        var id: String { name }
        var brand: LocalModelBrand? { LocalModelBrand.detect(modelName: name) }

        var memoryText: String {
            guard let memoryBytes else { return "—" }
            let units: [(String, Double)] = [
                ("EB", pow(1024, 6)), ("PB", pow(1024, 5)),
                ("TB", pow(1024, 4)), ("GB", pow(1024, 3)),
                ("MB", pow(1024, 2)), ("KB", 1024), ("B", 1)
            ]
            let bytes = Double(memoryBytes)
            let (unit, divisor) = units.first { bytes >= $0.1 } ?? ("B", 1)
            let value = (bytes / divisor).formatted(.number.precision(.fractionLength(0...1)))
            return "\(value) \(unit)"
        }

        var contextText: String {
            contextLength.map { "\($0.formatted()) tokens" } ?? "Unavailable"
        }

        var quantizationText: String { quantizationLevel ?? "Unavailable" }

        var detail: String {
            "RAM \(memoryBytes == nil ? "unavailable" : memoryText) · Context limit \(contextText) · Quantization \(quantizationText)"
        }
    }

    let models: [Model]

    var summary: String {
        models.isEmpty ? "Server reachable · No models loaded"
            : "\(models.count) \(models.count == 1 ? "model" : "models") loaded"
    }
}
