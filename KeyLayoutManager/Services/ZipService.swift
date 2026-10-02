import Foundation

struct ZipEntry: Hashable {
    let path: String

    var isDirectory: Bool { path.hasSuffix("/") }
    var displayName: String { (path as NSString).lastPathComponent }
}

enum ZipServiceError: LocalizedError {
    case unsafeEntry(String)
    case toolFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .unsafeEntry(let path):
            return "Unsafe backup entry: \(path)"
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

        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        let archiveDir = destination.deletingLastPathComponent()
            .appendingPathComponent(".KeyLayoutManager-backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: archiveDir) }
        let archiveURL = archiveDir.appendingPathComponent("backup.zip")

        let manifestURL = stagingDir.appendingPathComponent(Self.manifestFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        _ = try await runProcess(executable: zipBinary,
                                 arguments: [
                                    "-rqy", archiveURL.path, ".",
                                    "-x", "*.DS_Store",
                                    "-x", "*/.DS_Store",
                                    "-x", "._*",
                                    "-x", "*/._*",
                                    "-x", "metadatacache.prmdc2*",
                                    "-x", "*/metadatacache.prmdc2*"
                                 ],
                                 cwd: sourceDir)

        _ = try await runProcess(executable: zipBinary,
                                 arguments: ["-jq", archiveURL.path, manifestURL.path],
                                 cwd: stagingDir)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: archiveURL)
        } else {
            try fm.moveItem(at: archiveURL, to: destination)
        }
    }

    func listEntries(zip: URL) async throws -> [ZipEntry] {
        let data = try await runProcess(executable: unzipBinary,
                                        arguments: ["-Z1", zip.path],
                                        cwd: nil)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let paths = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .filter { !Self.isExcluded(path: $0) }
        for path in paths { try Self.validateEntry(path) }
        return paths.map(ZipEntry.init(path:))
    }

    func extract(entries: [String],
                 from zip: URL,
                 into destinationDir: URL) async throws -> [String: URL] {
        let fileEntries = entries.filter { !$0.hasSuffix("/") && !Self.isExcluded(path: $0) }
        guard !fileEntries.isEmpty else { return [:] }

        for entry in fileEntries { try Self.validateEntry(entry) }
        // Reject archived links before unzip can use them as parent directories.
        let listing = try await runProcess(executable: unzipBinary,
            arguments: ["-Z", "-l", zip.path], cwd: nil)
        if String(decoding: listing, as: UTF8.self).split(separator: "\n").contains(where: { $0.hasPrefix("l") }) {
            throw ZipServiceError.unsafeEntry("Archive contains symbolic links")
        }
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        // unzip treats entry names as patterns; escape them for exact selection.
        let patterns = fileEntries.map { entry in
            entry.reduce(into: "") { result, character in
                if "\\*?[]".contains(character) { result.append("\\") }
                result.append(character)
            }
        }
        let arguments = ["-oq", zip.path] + patterns + ["-d", destinationDir.path]
        _ = try await runProcess(executable: unzipBinary, arguments: arguments, cwd: nil)

        var map: [String: URL] = [:]
        for entry in fileEntries {
            let url = destinationDir.appendingPathComponent(entry)
            let root = destinationDir.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
                  try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
                  try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw ZipServiceError.unsafeEntry(entry)
            }
            map[entry] = url
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

    private static func validateEntry(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.hasPrefix("-"),
              !path.contains("\\"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !components.contains("..") else {
            throw ZipServiceError.unsafeEntry(path)
        }
    }

    static func isExcluded(path: String) -> Bool {
        if path.hasPrefix("__MACOSX/") { return true }
        let filename = (path as NSString).lastPathComponent
        if filename == ".DS_Store" { return true }
        if filename.hasPrefix("._") { return true }
        if filename.hasPrefix("metadatacache.prmdc2") { return true }
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

            // File-backed output cannot fill a pipe and block the child before termination.
            let outputDir = fm.temporaryDirectory.appendingPathComponent("KeyLayoutManager-process-\(UUID().uuidString)")
            let stdoutURL = outputDir.appendingPathComponent("stdout")
            let stderrURL = outputDir.appendingPathComponent("stderr")
            let stdoutHandle: FileHandle
            let stderrHandle: FileHandle
            do {
                try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
                fm.createFile(atPath: stdoutURL.path, contents: nil)
                fm.createFile(atPath: stderrURL.path, contents: nil)
                stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                stderrHandle = try FileHandle(forWritingTo: stderrURL)
            } catch {
                try? fm.removeItem(at: outputDir)
                cont.resume(throwing: error)
                return
            }
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            process.terminationHandler = { proc in
                try? stdoutHandle.close()
                try? stderrHandle.close()
                defer { try? fm.removeItem(at: outputDir) }
                let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
                let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
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
                try? stdoutHandle.close()
                try? stderrHandle.close()
                try? fm.removeItem(at: outputDir)
                cont.resume(throwing: error)
            }
        }
    }
}
