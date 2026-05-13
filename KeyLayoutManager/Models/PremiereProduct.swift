import Foundation

enum PremiereProduct {
    static func productName(forVersion version: String) -> String {
        let major = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
        return major >= 26 ? "Premiere" : "Premiere Pro"
    }

    static func displayName(forVersion version: String) -> String {
        "\(productName(forVersion: version)) \(version)"
    }
}
