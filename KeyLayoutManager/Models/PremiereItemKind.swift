import Foundation

enum PremiereItemKind: String, Codable, CaseIterable, Hashable {
    case kys
    case sourcePatcher
    case workspace
}

extension PremiereItemKind {
    var fileExtension: String {
        switch self {
        case .kys: return "kys"
        case .sourcePatcher: return "sppreset"
        case .workspace: return "xml"
        }
    }

    var displayName: String {
        switch self {
        case .kys: return "Keyboard Layouts"
        case .sourcePatcher: return "Source Assignment Presets"
        case .workspace: return "Panel Layouts"
        }
    }

    var itemNoun: String {
        switch self {
        case .kys: return "keyboard layout"
        case .sourcePatcher: return "source assignment preset"
        case .workspace: return "panel layout"
        }
    }

    var profileSubpath: [String] {
        switch self {
        case .kys: return ["Mac"]
        case .sourcePatcher: return ["Settings", "Source Patcher Presets"]
        case .workspace: return ["Layouts"]
        }
    }

    var sfSymbol: String {
        switch self {
        case .kys: return "keyboard"
        case .sourcePatcher: return "rectangle.3.group"
        case .workspace: return "rectangle.split.3x1"
        }
    }

    /// XML is shared by many Adobe settings; only accept actual workspace documents.
    static func kind(forFile url: URL) -> PremiereItemKind? {
        guard let kind = kind(forFileExtension: url.pathExtension) else { return nil }
        guard kind == .workspace else { return kind }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let parser = XMLParser(contentsOf: url) else { return nil }
        let detector = WorkspaceDetector()
        parser.delegate = detector
        parser.shouldResolveExternalEntities = false
        return parser.parse() && detector.isWorkspace ? kind : nil
    }

    static func kind(forFileExtension ext: String) -> PremiereItemKind? {
        let lower = ext.lowercased()
        return Self.allCases.first { $0.fileExtension == lower }
    }
}

private final class WorkspaceDetector: NSObject, XMLParserDelegate {
    private var inKey = false
    private var key = ""
    var isWorkspace = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        inKey = elementName == "key"
        if inKey { key = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inKey { key += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "key" {
            if key.trimmingCharacters(in: .whitespacesAndNewlines) == "DVA_Wrkspce" { isWorkspace = true }
            inKey = false
        }
    }
}
