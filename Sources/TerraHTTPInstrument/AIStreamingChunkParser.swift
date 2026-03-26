import Foundation

enum AIStreamingChunkParser {
    static func outputTokens(from data: Data) -> Int? {
        if let parsed = AIResponseParser.parse(data: data), let outputTokens = parsed.outputTokens {
            return outputTokens
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }

            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let payloadData = payload.data(using: .utf8) else { continue }
            if let parsed = AIResponseParser.parse(data: payloadData), let outputTokens = parsed.outputTokens {
                return outputTokens
            }
        }

        return nil
    }
}
