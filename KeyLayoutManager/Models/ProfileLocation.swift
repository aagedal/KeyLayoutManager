import Foundation

struct ProfileLocation: Identifiable, Hashable {
    let version: String
    let profileName: String
    let profileRootURL: URL

    var id: String { "\(version)/\(profileName)" }

    var displayName: String {
        "\(PremiereProduct.displayName(forVersion: version)) — \(profileName)"
    }

    var macDirURL: URL { directoryURL(for: .kys) }

    func directoryURL(for kind: PremiereItemKind) -> URL {
        kind.profileSubpath.reduce(profileRootURL) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }
}
