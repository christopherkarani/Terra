import Foundation

struct AIRequestParser {
    static let maxBodySizeBytes = 10 * 1_048_576 // 10 MiB

    static func parse(body: Data) -> ParsedRequest? {
        guard body.count <= maxBodySizeBytes else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        let model = json["model"] as? String

        let maxTokens = intValue(
            json["max_tokens"]
                ?? json["max_completion_tokens"]
                ?? json["max_new_tokens"]
        )

        let temperature = doubleValue(json["temperature"])

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

private func intValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else {
        return nil
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return nil
    }
    let double = number.doubleValue
    guard double.isFinite else {
        return nil
    }
    let rounded = double.rounded(.towardZero)
    guard rounded == double else {
        return nil
    }
    let intValue = Int(rounded)
    guard Double(intValue) == rounded else {
        return nil
    }
    return intValue
}

private func doubleValue(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else {
        return nil
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return nil
    }
    let double = number.doubleValue
    return double.isFinite ? double : nil
}

struct ParsedRequest: Sendable {
    let model: String?
    let maxTokens: Int?
    let temperature: Double?
    let stream: Bool?
}
