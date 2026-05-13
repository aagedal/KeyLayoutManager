import Foundation

enum CloudTargets {
    static let backupSubfolder = "KeyLayoutManager"

    static func iCloudDrive(fileManager: FileManager = .default) -> URL? {
        let url = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    static func dropbox(fileManager: FileManager = .default) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            "Library/CloudStorage/Dropbox",
            "Library/CloudStorage/Dropbox-Personal",
            "Library/CloudStorage/Dropbox-Business",
            "Dropbox",
        ]
        return candidates
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    static func backupDirectory(root: URL, version: String) -> URL {
        root.appendingPathComponent(backupSubfolder, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }
}
