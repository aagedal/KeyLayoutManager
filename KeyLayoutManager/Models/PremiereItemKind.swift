import Foundation

enum PremiereItemKind: String, Codable, CaseIterable, Hashable {
    case kys
    case sourcePatcher
}

extension PremiereItemKind {
    var fileExtension: String {
        switch self {
        case .kys: return "kys"
        case .sourcePatcher: return "sppreset"
        }
    }

    var displayName: String {
        switch self {
        case .kys: return "Keyboard Layouts"
        case .sourcePatcher: return "Source Assignment Presets"
        }
    }

    var itemNoun: String {
        switch self {
        case .kys: return "keyboard layout"
        case .sourcePatcher: return "source assignment preset"
        }
    }

    var profileSubpath: [String] {
        switch self {
        case .kys: return ["Mac"]
        case .sourcePatcher: return ["Settings", "Source Patcher Presets"]
        }
    }

    var sfSymbol: String {
        switch self {
        case .kys: return "keyboard"
        case .sourcePatcher: return "rectangle.3.group"
        }
    }

    static func kind(forFileExtension ext: String) -> PremiereItemKind? {
        let lower = ext.lowercased()
        return Self.allCases.first { $0.fileExtension == lower }
    }
}
