import Foundation

/// Git diff operations for session review — runs git commands via subprocess
@MainActor
final class GitDiffService: ObservableObject {
    static let shared = GitDiffService()

    /// Get diff stats for a specific file (e.g. "+12 -3")
    func diffStat(for path: String, in directory: String) async -> String? {
        guard let output = await runGit(["diff", "--stat", "--", path], in: directory) else { return nil }
        // Parse last line: " file.swift | 15 +++++---" → extract "+N -N"
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let summary = lines.last else { return nil }
        // Look for "N insertions(+), N deletions(-)" pattern in the summary line
        if summary.contains("changed") {
            var parts: [String] = []
            if let insertMatch = summary.range(of: "(\\d+) insertion", options: .regularExpression) {
                let num = summary[insertMatch].components(separatedBy: " ").first ?? "0"
                parts.append("+\(num)")
            }
            if let deleteMatch = summary.range(of: "(\\d+) deletion", options: .regularExpression) {
                let num = summary[deleteMatch].components(separatedBy: " ").first ?? "0"
                parts.append("-\(num)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        // Fallback: parse the per-file stat line "file | N ++--"
        if let pipeIdx = summary.range(of: "|") {
            let after = summary[pipeIdx.upperBound...].trimmingCharacters(in: .whitespaces)
            let plusCount = after.filter { $0 == "+" }.count
            let minusCount = after.filter { $0 == "-" }.count
            if plusCount > 0 || minusCount > 0 {
                return "+\(plusCount) -\(minusCount)"
            }
        }
        return nil
    }

    /// Get full unified diff for a specific file
    func diff(for path: String, in directory: String) async -> String? {
        await runGit(["diff", "--", path], in: directory)
    }

    /// Get full unified diff for all changes in the working directory
    func diffAll(in directory: String) async -> String? {
        await runGit(["diff"], in: directory)
    }

    /// Get list of changed files with their status
    func changedFiles(in directory: String) async -> [(path: String, status: String)] {
        // Both staged and unstaged
        guard let output = await runGit(["status", "--porcelain"], in: directory) else { return [] }
        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard line.count >= 3 else { return nil }
                let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                let path = String(line.dropFirst(3))
                return (path: path, status: status)
            }
    }

    /// Revert a specific file (git checkout -- <path>)
    func revert(path: String, in directory: String) async -> Bool {
        let result = await runGit(["checkout", "--", path], in: directory)
        return result != nil
    }

    /// Stage all and commit with message
    func commit(message: String, in directory: String) async -> Bool {
        // Stage all changes
        guard await runGit(["add", "-A"], in: directory) != nil else { return false }
        // Commit
        let result = await runGit(["commit", "-m", message], in: directory)
        return result != nil
    }

    /// Get diff stat summary (e.g. "5 files changed, +142 -38")
    func diffStatSummary(in directory: String) async -> String? {
        guard let output = await runGit(["diff", "--stat"], in: directory) else { return nil }
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.last // The summary line
    }

    // MARK: - Subprocess

    private func runGit(_ args: [String], in directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: directory)

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                proc.environment = env

                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (output?.isEmpty ?? true) ? nil : output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
