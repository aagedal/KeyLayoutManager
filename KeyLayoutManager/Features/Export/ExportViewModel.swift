import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class ExportViewModel {
    var installs: [PremiereInstall] = []
    var selection: Set<URL> = []
    var iCloudURL: URL?
    var dropboxURL: URL?
    var statusMessage: String?
    var errorMessage: String?

    private let scanner: PremiereScanner
    private let copier = CopyService()
    private let stage = TempStage.shared

    init(scanner: PremiereScanner = PremiereScanner()) {
        self.scanner = scanner
    }

    var allLayouts: [KeyboardLayout] {
        (try? scanner.scanLayouts()) ?? []
    }

    var selectedLayouts: [KeyboardLayout] {
        allLayouts.filter { selection.contains($0.fileURL) }
    }

    func refresh() {
        installs = (try? scanner.scan()) ?? []
        iCloudURL = CloudTargets.iCloudDrive()
        dropboxURL = CloudTargets.dropbox()
    }

    func stagedURL(for layout: KeyboardLayout) -> URL {
        (try? stage.stage(layout.fileURL)) ?? layout.fileURL
    }

    func exportToFolder() async {
        guard !selectedLayouts.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to copy the selected keyboard layouts to."
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        await copyAll(into: dest, policyForFirst: .prompt)
    }

    func backupToICloud() async {
        guard let root = iCloudURL, let version = primaryVersion() else { return }
        let dest = CloudTargets.backupDirectory(root: root, version: version)
        await copyAll(into: dest, policyForFirst: .prompt)
    }

    func backupToDropbox() async {
        guard let root = dropboxURL, let version = primaryVersion() else { return }
        let dest = CloudTargets.backupDirectory(root: root, version: version)
        await copyAll(into: dest, policyForFirst: .prompt)
    }

    private func primaryVersion() -> String? {
        selectedLayouts.first?.origin.version
    }

    private var applyToAllPolicy: CollisionPolicy?

    func dropOnProfile(urls: [URL], profile: ProfileLocation) async {
        let kys = urls.filter { $0.pathExtension.lowercased() == "kys" }
        guard !kys.isEmpty else { return }
        await copyURLs(kys, into: profile.macDirURL, contextLabel: profile.displayName)
        refresh()
    }

    private func copyAll(into dest: URL, policyForFirst: CollisionPolicy) async {
        await copyURLs(selectedLayouts.map(\.fileURL), into: dest, contextLabel: dest.path)
    }

    private func copyURLs(_ urls: [URL], into dest: URL, contextLabel: String) async {
        applyToAllPolicy = nil
        var copied = 0, renamed = 0, skipped = 0
        for url in urls {
            let policy: CollisionPolicy = applyToAllPolicy ?? .prompt
            do {
                let outcome = try await copier.copy(url, into: dest, policy: policy) { [weak self] target in
                    guard let self else { return .skip }
                    let result = await self.promptCollision(targetURL: target)
                    if result.applyToAll { await self.setApplyToAll(result.policy) }
                    return result.policy
                }
                switch outcome {
                case .copied: copied += 1
                case .renamed: renamed += 1
                case .skipped: skipped += 1
                }
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        statusMessage = summary(copied: copied, renamed: renamed, skipped: skipped, label: contextLabel)
    }

    private func setApplyToAll(_ policy: CollisionPolicy) {
        applyToAllPolicy = policy
    }

    private func summary(copied: Int, renamed: Int, skipped: Int, label: String) -> String {
        var parts: [String] = []
        if copied > 0 { parts.append("\(copied) copied") }
        if renamed > 0 { parts.append("\(renamed) renamed") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        let summary = parts.isEmpty ? "Nothing to do" : parts.joined(separator: ", ")
        return "\(summary) → \(label)"
    }

    private func promptCollision(targetURL: URL) async -> (policy: CollisionPolicy, applyToAll: Bool) {
        await withCheckedContinuation { (cont: CheckedContinuation<(CollisionPolicy, Bool), Never>) in
            let alert = NSAlert()
            alert.messageText = "\"\(targetURL.lastPathComponent)\" already exists."
            alert.informativeText = "Choose what to do with this file."
            alert.alertStyle = .warning
            let overwrite = alert.addButton(withTitle: "Overwrite")
            overwrite.hasDestructiveAction = true
            alert.addButton(withTitle: "Keep both")
            alert.addButton(withTitle: "Skip")
            let toggle = NSButton(checkboxWithTitle: "Apply to all remaining", target: nil, action: nil)
            toggle.state = .off
            alert.accessoryView = toggle
            let response = alert.runModal()
            let policy: CollisionPolicy = {
                switch response {
                case .alertFirstButtonReturn: return .overwrite
                case .alertSecondButtonReturn: return .keepBoth
                default: return .skip
                }
            }()
            cont.resume(returning: (policy, toggle.state == .on))
        }
    }
}
