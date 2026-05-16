import CoreML
import Foundation

struct BenchmarkResult: Codable {
    let model_id: String
    let compute_units: String
    let warmup: Int
    let runs: Int
    let median_ms: Double
    let mean_ms: Double
    let std_ms: Double
    let p90_ms: Double
    let p95_ms: Double
    let min_ms: Double
    let max_ms: Double
    let latencies_ms: [Double]
}

final class ModelBenchmarker {
    private let fileManager = FileManager.default

    func benchmark(upload data: Data, query: [String: String]) throws -> BenchmarkResult {
        let modelID = sanitize(query["model_id"] ?? "uploaded_model")
        let warmup = Int(query["warmup"] ?? "10") ?? 10
        let runs = Int(query["runs"] ?? "50") ?? 50
        let computeUnitsName = query["compute_units"] ?? "all"
        let computeUnits = parseComputeUnits(computeUnitsName)

        let root = try documentsDirectory().appendingPathComponent("LatencyBench", isDirectory: true)
        let uploads = root.appendingPathComponent("Uploaded", isDirectory: true)
        let compiled = root.appendingPathComponent("Compiled", isDirectory: true)
        try fileManager.createDirectory(at: uploads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: compiled, withIntermediateDirectories: true)

        let uploadURL = uploads.appendingPathComponent("\(modelID).mlmodel")
        try data.write(to: uploadURL, options: [.atomic])

        let compiledURL = try MLModel.compileModel(at: uploadURL)
        let stableCompiledURL = compiled.appendingPathComponent("\(modelID).mlmodelc", isDirectory: true)
        if fileManager.fileExists(atPath: stableCompiledURL.path) {
            try fileManager.removeItem(at: stableCompiledURL)
        }
        try fileManager.copyItem(at: compiledURL, to: stableCompiledURL)

        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: stableCompiledURL, configuration: configuration)
        let input = try makeInputProvider(for: model)

        for _ in 0..<max(0, warmup) {
            _ = try model.prediction(from: input)
        }

        var timings: [Double] = []
        timings.reserveCapacity(max(0, runs))
        for _ in 0..<max(0, runs) {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try model.prediction(from: input)
            let end = DispatchTime.now().uptimeNanoseconds
            timings.append(Double(end - start) / 1_000_000.0)
        }

        return BenchmarkResult(
            model_id: modelID,
            compute_units: computeUnitsName,
            warmup: warmup,
            runs: runs,
            median_ms: percentile(timings, 0.50),
            mean_ms: mean(timings),
            std_ms: std(timings),
            p90_ms: percentile(timings, 0.90),
            p95_ms: percentile(timings, 0.95),
            min_ms: timings.min() ?? 0,
            max_ms: timings.max() ?? 0,
            latencies_ms: timings
        )
    }

    private func makeInputProvider(for model: MLModel) throws -> MLFeatureProvider {
        guard let inputDescription = model.modelDescription.inputDescriptionsByName.first else {
            throw NSError(domain: "LatencyBench", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model has no input."])
        }
        let inputName = inputDescription.key
        let feature = inputDescription.value
        guard let constraint = feature.multiArrayConstraint else {
            throw NSError(
                domain: "LatencyBench",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Expected MLMultiArray input for \(inputName)."]
            )
        }
        let shape = constraint.shape.map { NSNumber(value: $0.intValue) }
        let array = try MLMultiArray(shape: shape, dataType: constraint.dataType)
        for i in 0..<array.count {
            array[i] = NSNumber(value: 0.0)
        }
        return try MLDictionaryFeatureProvider(dictionary: [inputName: array])
    }

    private func parseComputeUnits(_ name: String) -> MLComputeUnits {
        switch name {
        case "cpuOnly":
            return .cpuOnly
        case "cpuAndGPU":
            return .cpuAndGPU
        case "cpuAndNeuralEngine":
            if #available(iOS 16.0, *) {
                return .cpuAndNeuralEngine
            }
            return .all
        default:
            return .all
        }
    }

    private func documentsDirectory() throws -> URL {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "LatencyBench", code: 3, userInfo: [NSLocalizedDescriptionKey: "No documents directory."])
        }
        return url
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        return String(
            value.map { character in
                character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "_"
            }
        )
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func std(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mu = mean(values)
        let variance = values.map { ($0 - mu) * ($0 - mu) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(max(Int((Double(sorted.count - 1) * p).rounded()), 0), sorted.count - 1)
        return sorted[index]
    }
}
