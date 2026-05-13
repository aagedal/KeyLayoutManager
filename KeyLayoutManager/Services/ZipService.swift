import Foundation

struct ZipEntry: Hashable {
    let path: String

    var isDirectory: Bool { path.hasSuffix("/") }
    var displayName: String { (path as NSString).lastPathComponent }
}

enum ZipServiceError: LocalizedError {
    case toolFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .toolFailed(let command, let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) exited with status \(exitCode)"
                : "\(command) exited with status \(exitCode): \(detail)"
        }
    }
}

struct ZipService {
    static let manifestFilename = "KeyLayoutManager-manifest.json"

    private let zipBinary = URL(fileURLWithPath: "/usr/bin/zip")
    private let unzipBinary = URL(fileURLWithPath: "/usr/bin/unzip")
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    func createZip(contents sourceDir: URL,
                   manifest: BackupManifest,
                   to destination: URL) async throws {
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("KeyLayoutManager-zip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingDir) }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        let manifestURL = stagingDir.appendingPathComponent(Self.manifestFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        _ = try await runProcess(executable: zipBinary,
                                 arguments: [
                                    "-rqy", destination.path, ".",
                                    "-x", "*.DS_Store",
                                    "-x", "*/.DS_Store",
                                    "-x", "._*",
                                    "-x", "*/._*"
                                 ],
                                 cwd: sourceDir)

        _ = try await runProcess(executable: zipBinary,
                                 arguments: ["-jq", destination.path, manifestURL.path],
                                 cwd: stagingDir)
    }

    func listEntries(zip: URL) async throws -> [ZipEntry] {
        let data = try await runProcess(executable: unzipBinary,
                                        arguments: ["-Z1", zip.path],
                                        cwd: nil)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .filter { !Self.isMacMetadata(path: $0) }
            .map(ZipEntry.init(path:))
    }

    func extract(entries: [String],
                 from zip: URL,
                 into destinationDir: URL) async throws -> [String: URL] {
        let fileEntries = entries.filter { !$0.hasSuffix("/") && !Self.isMacMetadata(path: $0) }
        guard !fileEntries.isEmpty else { return [:] }

        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let arguments = ["-oq", zip.path] + fileEntries + ["-d", destinationDir.path]
        _ = try await runProcess(executable: unzipBinary, arguments: arguments, cwd: nil)

        var map: [String: URL] = [:]
        for entry in fileEntries {
            map[entry] = destinationDir.appendingPathComponent(entry)
        }
        return map
    }

    func readManifest(zip: URL) async -> BackupManifest? {
        let data = (try? await runProcess(executable: unzipBinary,
                                          arguments: ["-p", zip.path, Self.manifestFilename],
                                          cwd: nil)) ?? Data()
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupManifest.self, from: data)
    }

    static func isMacMetadata(path: String) -> Bool {
        if path.hasPrefix("__MACOSX/") { return true }
        let filename = (path as NSString).lastPathComponent
        if filename == ".DS_Store" { return true }
        if filename.hasPrefix("._") { return true }
        return false
    }

    @discardableResult
    private func runProcess(executable: URL,
                            arguments: [String],
                            cwd: URL?) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                if proc.terminationStatus == 0 {
                    cont.resume(returning: stdoutData)
                } else {
                    let command = ([executable.path] + arguments).joined(separator: " ")
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                    cont.resume(throwing: ZipServiceError.toolFailed(
                        command: command,
                        exitCode: proc.terminationStatus,
                        stderr: stderrString
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
