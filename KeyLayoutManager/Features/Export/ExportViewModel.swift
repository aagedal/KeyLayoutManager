import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

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
    private let zipService = ZipService()
    private let stage = TempStage.shared

    init(scanner: PremiereScanner = PremiereScanner()) {
        self.scanner = scanner
    }

    var allLayouts: [KeyboardLayout] {
        (try? scanner.scanItems(of: .kys)) ?? []
    }

    var allPresets: [KeyboardLayout] {
        (try? scanner.scanItems(of: .sourcePatcher)) ?? []
    }

    var allItems: [KeyboardLayout] {
        PremiereItemKind.allCases.flatMap { (try? scanner.scanItems(of: $0)) ?? [] }
    }

    var selectedItems: [KeyboardLayout] {
        allItems.filter { selection.contains($0.fileURL) }
    }

    func items(for profile: ProfileLocation, kind: PremiereItemKind) -> [KeyboardLayout] {
        ((try? scanner.scanItems(of: kind)) ?? []).filter { $0.origin.id == profile.id }
    }

    func refresh() {
        installs = (try? scanner.scan()) ?? []
        iCloudURL = CloudTargets.iCloudDrive()
        dropboxURL = CloudTargets.dropbox()
    }

    func stagedURL(for item: KeyboardLayout) -> URL {
        (try? stage.stage(item.fileURL)) ?? item.fileURL
    }

    func exportToFolder() async {
        guard !selectedItems.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to copy the selected items to."
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let pairs = selectedItems.map { ($0.fileURL, dest) }
        await copyPairs(pairs, contextLabel: dest.path)
    }

    func backupToICloud() async {
        guard let root = iCloudURL, let version = primaryVersion() else { return }
        let dest = CloudTargets.backupDirectory(root: root, version: version)
        let pairs = selectedItems.map { ($0.fileURL, dest) }
        await copyPairs(pairs, contextLabel: dest.path)
    }

    func backupToDropbox() async {
        guard let root = dropboxURL, let version = primaryVersion() else { return }
        let dest = CloudTargets.backupDirectory(root: root, version: version)
        let pairs = selectedItems.map { ($0.fileURL, dest) }
        await copyPairs(pairs, contextLabel: dest.path)
    }

    private func primaryVersion() -> String? {
        selectedItems.first?.origin.version
    }

    private var applyToAllPolicy: CollisionPolicy?

    func dropOnProfile(urls: [URL], profile: ProfileLocation) async {
        var pairs: [(URL, URL)] = []
        for url in urls {
            guard let kind = PremiereItemKind.kind(forFile: url) else { continue }
            pairs.append((url, profile.directoryURL(for: kind)))
        }
        guard !pairs.isEmpty else { return }
        await copyPairs(pairs, contextLabel: profile.displayName)
        refresh()
    }

    func backupProfile(_ profile: ProfileLocation) async {
        let panel = NSSavePanel()
        if let zipType = UTType("public.zip-archive") {
            panel.allowedContentTypes = [zipType]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(PremiereProduct.displayName(forVersion: profile.version)) — \(profile.profileName).zip"
        panel.prompt = "Back Up"
        panel.message = "Save a full backup of \"\(profile.profileName)\" (\(PremiereProduct.displayName(forVersion: profile.version)))."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        statusMessage = nil
        errorMessage = nil

        let manifest = BackupManifest(
            appVersion: BackupManifest.currentAppVersion(),
            sourceVersion: profile.version,
            sourceProfileName: profile.profileName
        )

        do {
            try await zipService.createZip(contents: profile.profileRootURL,
                                           manifest: manifest,
                                           to: destination)
            statusMessage = "Backed up \"\(profile.profileName)\" → \(destination.lastPathComponent)"
        } catch {
            errorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    func deleteProfile(_ profile: ProfileLocation) async {
        let profileDir = profile.profileRootURL

        let alert = NSAlert()
        alert.messageText = "Delete profile \"\(profile.profileName)\"?"
        alert.informativeText = "This moves the entire profile folder for \(PremiereProduct.displayName(forVersion: profile.version)) to the Trash, including all of its keyboard shortcuts and other settings. You can recover it from the Trash."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Move to Trash")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            _ = try await NSWorkspace.shared.recycle([profileDir])
            statusMessage = "Moved \"\(profile.profileName)\" to Trash."
            errorMessage = nil
            selection = selection.filter { !$0.path.hasPrefix(profileDir.path) }
            refresh()
        } catch {
            errorMessage = "Couldn't delete \"\(profile.profileName)\": \(error.localizedDescription)"
        }
    }

    private func copyPairs(_ pairs: [(source: URL, destination: URL)], contextLabel: String) async {
        applyToAllPolicy = nil
        var copied = 0, renamed = 0, skipped = 0
        for (source, destination) in pairs {
            let policy: CollisionPolicy = applyToAllPolicy ?? .prompt
            do {
                let outcome = try await copier.copy(source, into: destination, policy: policy) { [weak self] target in
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
                errorMessage = "\(source.lastPathComponent): \(error.localizedDescription)"
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
