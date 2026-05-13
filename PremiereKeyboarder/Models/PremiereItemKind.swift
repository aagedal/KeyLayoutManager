import Foundation

enum PremiereItemKind: String, Codable, CaseIterable, Hashable {
    case kys
    // Future: case workspace, case preset
}

extension PremiereItemKind {
    var fileExtension: String {
        switch self {
        case .kys: return "kys"
        }
    }
}
