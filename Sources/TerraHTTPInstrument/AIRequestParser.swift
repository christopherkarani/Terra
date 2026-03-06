import Foundation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "AIRequestParser")

struct AIRequestParser {
    static let maxBodySizeBytes = 10 * 1_048_576 // 10 MiB

    static func parse(body: Data) -> ParsedRequest? {
        guard body.count <= maxBodySizeBytes else {
            logger.debug("Request body exceeds max size: \(body.count) bytes")
            return nil
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }
            json = parsed
        } catch {
            logger.debug("Failed to parse request JSON: \(error.localizedDescription)")
            return nil
        }

        let model = json["model"] as? String

        let maxTokens: Int?
        if let v = intValue(json["max_tokens"]) {
            maxTokens = v
        } else if let v = intValue(json["max_completion_tokens"]) {
            maxTokens = v
        } else if let v = intValue(json["max_new_tokens"]) {
            maxTokens = v
        } else {
            maxTokens = nil
        }

        let temperature: Double?
        if let v = doubleValue(json["temperature"]) {
            temperature = v
        } else {
            temperature = nil
        }

        let stream = json["stream"] as? Bool

        guard model != nil || maxTokens != nil || temperature != nil || stream != nil else {
            return nil
        }

        return ParsedRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            stream: stream
        )
    }
}

struct ParsedRequest: Sendable {
    let model: String?
    let maxTokens: Int?
    let temperature: Double?
    let stream: Bool?
}

private func intValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else {
        return nil
    }

    if isBoolean(number) {
        return nil
    }

    let doubleValue = number.doubleValue
    guard doubleValue.isFinite else {
        return nil
    }

    let rounded = doubleValue.rounded()
    guard rounded == doubleValue else {
        return nil
    }

    return Int(rounded)
}

private func doubleValue(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else {
        return nil
    }

    if isBoolean(number) {
        return nil
    }

    let doubleValue = number.doubleValue
    guard doubleValue.isFinite else {
        return nil
    }

    return doubleValue
}

private func isBoolean(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
}
