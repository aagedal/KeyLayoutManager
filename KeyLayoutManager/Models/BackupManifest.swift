import Foundation

struct BackupManifest: Codable, Hashable {
    static let currentSchemaVersion = 1
    static let kindFullProfile = "full-profile"

    var schemaVersion: Int
    var appVersion: String
    var createdAt: Date
    var sourceVersion: String
    var sourceProfileName: String
    var kind: String

    init(schemaVersion: Int = BackupManifest.currentSchemaVersion,
         appVersion: String,
         createdAt: Date = Date(),
         sourceVersion: String,
         sourceProfileName: String,
         kind: String = BackupManifest.kindFullProfile) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.sourceVersion = sourceVersion
        self.sourceProfileName = sourceProfileName
        self.kind = kind
    }
}

extension BackupManifest {
    static func currentAppVersion(bundle: Bundle = .main) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (v?, b?): return "\(v) (\(b))"
        case let (v?, nil): return v
        case let (nil, b?): return b
        default: return "unknown"
        }
    }
}
