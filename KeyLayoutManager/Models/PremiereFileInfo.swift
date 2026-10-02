import Foundation

enum PremiereFileInfo {
    static func description(for relativePath: String) -> String? {
        let filename = (relativePath as NSString).lastPathComponent
        let ext = (relativePath as NSString).pathExtension.lowercased()
        let lowerPath = relativePath.lowercased()

        if let kind = PremiereItemKind.kind(forFileExtension: ext), kind != .workspace {
            return kindDescription(kind)
        }

        if filename == "Adobe Premiere Pro Prefs" {
            return "Main Premiere preferences — global app settings (panels, recents, defaults)."
        }
        if filename.hasPrefix("metadatacache.prmdc2") {
            return "Local metadata cache (SQLite). Premiere regenerates this on demand — usually safe to skip when restoring."
        }
        if filename == "SharedView Column Settings" {
            return "Column layout for list views like the Project panel."
        }
        if filename == "Media Browser Provider Exception" {
            return "Per-provider exceptions used by Premiere's Media Browser."
        }

        if ext == "guides" {
            return "Premiere Guides state — tracks which in-app tutorials you've seen."
        }
        if ext == "prfpset" {
            return "Premiere effect preset."
        }
        if ext == "prfm" {
            return "Premiere transform or motion preset."
        }
        if ext == "xmp" {
            return "Adobe XMP sidecar metadata."
        }

        if lowerPath.contains("workspaces/") || lowerPath.contains("layouts/") {
            return "Workspace or panel layout."
        }
        if lowerPath.contains("effects presets/") {
            return "Custom effects preset."
        }
        if lowerPath.contains("source patcher presets/") {
            return "Source Assignment preset for the Source Monitor patcher."
        }

        return nil
    }

    private static func kindDescription(_ kind: PremiereItemKind) -> String {
        switch kind {
        case .kys:
            return "Keyboard shortcut layout — your saved key bindings for Premiere."
        case .workspace:
            return "Panel layout — saved arrangement of Premiere panels and windows."
        case .sourcePatcher:
            return "Source Assignment preset — how source channels map onto sequence tracks."
        }
    }
}
