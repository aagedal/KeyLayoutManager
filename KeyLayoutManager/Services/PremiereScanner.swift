import Foundation

struct PremiereScanner {
    let documentsRoot: URL
    private let fm: FileManager

    init(documentsRoot: URL? = nil, fileManager: FileManager = .default) {
        self.fm = fileManager
        if let documentsRoot {
            self.documentsRoot = documentsRoot
        } else {
            self.documentsRoot = (try? fileManager.url(for: .documentDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false))
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        }
    }

    var premiereRoot: URL {
        documentsRoot
            .appendingPathComponent("Adobe", isDirectory: true)
            .appendingPathComponent("Premiere Pro", isDirectory: true)
    }

    func scan() throws -> [PremiereInstall] {
        guard fm.fileExists(atPath: premiereRoot.path) else { return [] }
        let versionDirs = try listVersionDirectories()
        return versionDirs.map { versionURL -> PremiereInstall in
            let version = versionURL.lastPathComponent
            let profiles = (try? listProfiles(in: versionURL, version: version)) ?? []
            return PremiereInstall(version: version, profiles: profiles)
        }
    }

    func scanLayouts() throws -> [KeyboardLayout] {
        try scanItems(of: .kys)
    }

    func scanItems(of kind: PremiereItemKind) throws -> [KeyboardLayout] {
        try scan().flatMap { install in
            install.profiles.flatMap { profile in
                items(in: profile, kind: kind)
            }
        }
    }

    func destinations() throws -> [ProfileLocation] {
        try scan().flatMap(\.profiles)
    }

    // MARK: - Internals

    private func listVersionDirectories() throws -> [URL] {
        let regex = try NSRegularExpression(pattern: #"^\d+(\.\d+)+$"#)
        let entries = try fm.contentsOfDirectory(at: premiereRoot,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])
        let versions = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && regex.firstMatch(in: url.lastPathComponent,
                                    range: NSRange(location: 0, length: url.lastPathComponent.utf16.count)) != nil
        }
        return versions.sorted { a, b in
            let ta = Self.versionTuple(a.lastPathComponent)
            let tb = Self.versionTuple(b.lastPathComponent)
            return tb.lexicographicallyPrecedes(ta)
        }
    }

    private func listProfiles(in versionURL: URL, version: String) throws -> [ProfileLocation] {
        let entries = try fm.contentsOfDirectory(at: versionURL,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])
        return entries.compactMap { url -> ProfileLocation? in
            let name = url.lastPathComponent
            guard name.hasPrefix("Profile-"),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let profileName = String(name.dropFirst("Profile-".count))
            return ProfileLocation(version: version, profileName: profileName, profileRootURL: url)
        }
        .sorted { $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending }
    }

    private func items(in profile: ProfileLocation, kind: PremiereItemKind) -> [KeyboardLayout] {
        let directory = profile.directoryURL(for: kind)
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let entries = (try? fm.contentsOfDirectory(at: directory,
                                                   includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url -> KeyboardLayout? in
            guard url.pathExtension.lowercased() == kind.fileExtension else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? .distantPast
            return KeyboardLayout(fileURL: url, byteSize: size, modified: modified, origin: profile, kind: kind)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func versionTuple(_ s: String) -> [Int] {
        s.split(separator: ".").compactMap { Int($0) }
    }
}
