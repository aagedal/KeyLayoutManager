import Foundation

final class TempStage {
    static let shared = TempStage()

    private let stageRoot: URL
    private var stagedByFile: [URL: URL] = [:]
    private let lock = NSLock()
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
        self.stageRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyLayoutManager-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: stageRoot, withIntermediateDirectories: true)
    }

    func stage(_ source: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stagedByFile[source], fm.fileExists(atPath: existing.path) {
            return existing
        }
        let target = stageRoot.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: target)
        }
        try fm.copyItem(at: source, to: target)
        stagedByFile[source] = target
        return target
    }

    func wipe() {
        lock.lock()
        defer { lock.unlock() }
        try? fm.removeItem(at: stageRoot)
        stagedByFile.removeAll()
    }
}
