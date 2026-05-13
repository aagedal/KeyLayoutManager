import Foundation

struct IncomingItem: Identifiable, Hashable {
    enum Source: Hashable {
        case looseFile(URL)
        case zipEntry(zipURL: URL, entryPath: String)
    }

    let id: UUID
    let displayName: String
    let relativePath: String
    let source: Source
    var isSelected: Bool

    init(id: UUID = UUID(),
         displayName: String,
         relativePath: String,
         source: Source,
         isSelected: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.relativePath = relativePath
        self.source = source
        self.isSelected = isSelected
    }

    var topLevelGroup: String {
        let comps = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        if comps.count > 1 { return String(comps[0]) }
        return "(profile root)"
    }

    var parentRelativePath: String {
        let comps = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return comps.dropLast().joined(separator: "/")
    }

    var fileExtensionLowercased: String {
        (displayName as NSString).pathExtension.lowercased()
    }

    var kindHint: PremiereItemKind? {
        PremiereItemKind.kind(forFileExtension: fileExtensionLowercased)
    }
}

extension IncomingItem {
    static func looseFile(url: URL, kind: PremiereItemKind) -> IncomingItem {
        let subpath = kind.profileSubpath.joined(separator: "/")
        let filename = url.lastPathComponent
        let relative = subpath.isEmpty ? filename : "\(subpath)/\(filename)"
        return IncomingItem(displayName: filename,
                            relativePath: relative,
                            source: .looseFile(url))
    }

    static func zipEntry(zipURL: URL, entryPath: String) -> IncomingItem {
        let name = (entryPath as NSString).lastPathComponent
        return IncomingItem(displayName: name,
                            relativePath: entryPath,
                            source: .zipEntry(zipURL: zipURL, entryPath: entryPath))
    }
}
