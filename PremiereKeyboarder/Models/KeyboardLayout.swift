import Foundation

struct KeyboardLayout: Identifiable, Hashable {
    let fileURL: URL
    let displayName: String
    let byteSize: Int64
    let modified: Date
    let origin: ProfileLocation
    let kind: PremiereItemKind

    var id: URL { fileURL }

    init(fileURL: URL, byteSize: Int64, modified: Date, origin: ProfileLocation, kind: PremiereItemKind = .kys) {
        self.fileURL = fileURL
        self.displayName = fileURL.deletingPathExtension().lastPathComponent
        self.byteSize = byteSize
        self.modified = modified
        self.origin = origin
        self.kind = kind
    }
}
