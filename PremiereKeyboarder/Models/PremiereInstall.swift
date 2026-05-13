import Foundation

struct PremiereInstall: Identifiable, Hashable {
    let version: String
    let profiles: [ProfileLocation]

    var id: String { version }
}
