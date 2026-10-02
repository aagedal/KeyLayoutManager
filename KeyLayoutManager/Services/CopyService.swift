import Foundation

enum CollisionPolicy: Sendable {
    case overwrite
    case keepBoth
    case skip
    case prompt
}

enum CopyOutcome: Sendable, Equatable {
    case copied(URL)
    case renamed(URL)
    case skipped(URL)
}

struct CopyService {
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    func copy(_ source: URL,
              into destinationDir: URL,
              policy: CollisionPolicy,
              promptHandler: (@Sendable (URL) async -> CollisionPolicy)? = nil) async throws -> CopyOutcome {
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let target = destinationDir.appendingPathComponent(source.lastPathComponent)

        guard fm.fileExists(atPath: target.path) else {
            try fm.copyItem(at: source, to: target)
            return .copied(target)
        }

        let resolved: CollisionPolicy
        if policy == .prompt {
            guard let promptHandler else { return .skipped(target) }
            resolved = await promptHandler(target)
        } else {
            resolved = policy
        }

        switch resolved {
        case .overwrite:
            if source.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL {
                return .skipped(target)
            }
            let staging = destinationDir.appendingPathComponent(".KeyLayoutManager-copy-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: source, to: staging)
            _ = try fm.replaceItemAt(target, withItemAt: staging)
            return .copied(target)

        case .keepBoth:
            let renamed = Self.uniqueURL(for: target, in: destinationDir, fileManager: fm)
            try fm.copyItem(at: source, to: renamed)
            return .renamed(renamed)

        case .skip:
            return .skipped(target)

        case .prompt:
            return .skipped(target)
        }
    }

    static func uniqueURL(for target: URL, in directory: URL, fileManager: FileManager = .default) -> URL {
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var n = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }
}
