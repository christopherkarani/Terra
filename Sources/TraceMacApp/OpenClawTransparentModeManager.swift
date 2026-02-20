import Foundation

enum OpenClawTransparentModeError: LocalizedError {
    case invalidConfiguration(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .executionFailed(let message):
            return message
        }
    }
}

enum OpenClawTransparentModeManager {
    private static let anchor = "com.terra.redirect"
    private static let helperExecutable = "/Library/PrivilegedHelperTools/ai.openclaw.terra.pfhelper"

    static func enable(proxyPort: Int, targetPorts: [Int]) async -> Result<String, OpenClawTransparentModeError> {
        let sanitizedTargets = sanitizeTargetPorts(targetPorts, proxyPort: proxyPort)
        guard !sanitizedTargets.isEmpty else {
            return .failure(.invalidConfiguration("No valid target ports configured for transparent mode."))
        }

        if FileManager.default.isExecutableFile(atPath: helperExecutable) {
            let args = [
                "enable",
                "--anchor", anchor,
                "--proxy-port", "\(proxyPort)",
                "--target-ports", sanitizedTargets.map(String.init).joined(separator: ",")
            ]
            let helperResult = await runProcess(executablePath: helperExecutable, arguments: args)
            if helperResult.isSuccess {
                return .success("Transparent mode enabled with privileged helper.")
            }
            return .failure(.executionFailed("Privileged helper failed: \(helperResult.humanReadableFailure)"))
        }

        let rules = makeRules(proxyPort: proxyPort, targetPorts: sanitizedTargets)
        let command = "printf %s \(shellQuote(rules)) | /sbin/pfctl -a \(anchor) -f - && /sbin/pfctl -E"
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let result = await runProcess(executablePath: "/usr/bin/osascript", arguments: ["-e", script])
        if result.isSuccess {
            return .success("Transparent mode enabled using admin authorization.")
        }
        return .failure(.executionFailed("Could not enable transparent mode: \(result.humanReadableFailure)"))
    }

    static func disable() async -> Result<String, OpenClawTransparentModeError> {
        if FileManager.default.isExecutableFile(atPath: helperExecutable) {
            let helperResult = await runProcess(executablePath: helperExecutable, arguments: ["disable", "--anchor", anchor])
            if helperResult.isSuccess {
                return .success("Transparent mode disabled.")
            }
            return .failure(.executionFailed("Privileged helper failed: \(helperResult.humanReadableFailure)"))
        }

        let command = "/sbin/pfctl -a \(anchor) -F all -f /dev/null"
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let result = await runProcess(executablePath: "/usr/bin/osascript", arguments: ["-e", script])
        if result.isSuccess {
            return .success("Transparent mode disabled.")
        }
        return .failure(.executionFailed("Could not disable transparent mode: \(result.humanReadableFailure)"))
    }

    private static func sanitizeTargetPorts(_ ports: [Int], proxyPort: Int) -> [Int] {
        Array(Set(
            ports.filter { (1...65535).contains($0) && $0 != proxyPort }
        ))
        .sorted()
    }

    private static func makeRules(proxyPort: Int, targetPorts: [Int]) -> String {
        targetPorts
            .map {
                "rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port \($0) -> 127.0.0.1 port \(proxyPort)"
            }
            .joined(separator: "\n")
            + "\n"
    }

    private static func shellQuote(_ input: String) -> String {
        "'" + input.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptQuote(_ input: String) -> String {
        "\"" + input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }

    private static func runProcess(executablePath: String, arguments: [String]) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { runningProcess in
                continuation.resume(returning: runningProcess.terminationStatus)
            }
        }

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return CommandResult(status: status, stdout: stdout, stderr: stderr)
    }
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool {
        status == 0
    }

    var humanReadableFailure: String {
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }
        let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOut.isEmpty {
            return trimmedOut
        }
        return "exit code \(status)"
    }
}
