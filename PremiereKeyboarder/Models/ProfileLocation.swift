import Foundation

struct ProfileLocation: Identifiable, Hashable {
    let version: String
    let profileName: String
    let macDirURL: URL

    var id: String { "\(version)/\(profileName)" }

    var displayName: String { "\(version) — \(profileName)" }
}
