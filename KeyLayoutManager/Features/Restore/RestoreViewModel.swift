import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class RestoreViewModel {
    var incomingFiles: [URL] = []
    var destinations: [ProfileLocation] = []
    var selectedDestination: ProfileLocation?
    var iCloudURL: URL?
    var dropboxURL: URL?
    var statusMessage: String?
    var errorMessage: String?

    private let scanner: PremiereScanner
    private let copier = CopyService()

    init(scanner: PremiereScanner = PremiereScanner()) {
        self.scanner = scanner
    }

    func refresh() {
        destinations = (try? scanner.destinations()) ?? []
        if selectedDestination == nil || !destinations.contains(where: { $0.id == selectedDestination?.id }) {
            selectedDestination = destinations.first
        }
        iCloudURL = CloudTargets.iCloudDrive()
        dropboxURL = CloudTargets.dropbox()
    }

    func add(urls: [URL]) {
        let kys = urls.filter { $0.pathExtension.lowercased() == "kys" }
        var unique = incomingFiles
        for url in kys where !unique.contains(url) {
            unique.append(url)
        }
        incomingFiles = unique
    }

    func remove(_ url: URL) {
        incomingFiles.removeAll { $0 == url }
    }

    func clear() {
        incomingFiles.removeAll()
        statusMessage = nil
        errorMessage = nil
    }

    func chooseFiles() {
        runChooser(startingAt: nil, message: "Choose .kys keyboard layout files to restore.")
    }

    func chooseFromICloud() {
        guard let root = iCloudURL else { return }
        let backupRoot = root.appendingPathComponent(CloudTargets.backupSubfolder, isDirectory: true)
        let startURL = FileManager.default.fileExists(atPath: backupRoot.path) ? backupRoot : root
        runChooser(startingAt: startURL,
                   message: "Pick .kys backups from iCloud Drive.")
    }

    func chooseFromDropbox() {
        guard let root = dropboxURL else { return }
        let backupRoot = root.appendingPathComponent(CloudTargets.backupSubfolder, isDirectory: true)
        let startURL = FileManager.default.fileExists(atPath: backupRoot.path) ? backupRoot : root
        runChooser(startingAt: startURL,
                   message: "Pick .kys backups from Dropbox.")
    }

    private func runChooser(startingAt directoryURL: URL?, message: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let kysType = UTType(filenameExtension: "kys") {
            panel.allowedContentTypes = [kysType]
        }
        if let directoryURL { panel.directoryURL = directoryURL }
        panel.prompt = "Add"
        panel.message = message
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func performRestore() async {
        guard !incomingFiles.isEmpty else { return }
        guard let dest = selectedDestination else {
            errorMessage = "Pick a destination profile."
            return
        }
        statusMessage = nil
        errorMessage = nil

        applyToAllPolicy = nil
        var copied = 0, renamed = 0, skipped = 0

        for source in incomingFiles {
            let policy: CollisionPolicy = applyToAllPolicy ?? .prompt
            do {
                let outcome = try await copier.copy(source, into: dest.macDirURL, policy: policy) { [weak self] target in
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

        statusMessage = "Restored to \(dest.displayName): \(copied) copied, \(renamed) renamed, \(skipped) skipped."
        incomingFiles.removeAll()
    }

    private var applyToAllPolicy: CollisionPolicy?

    private func setApplyToAll(_ policy: CollisionPolicy) {
        applyToAllPolicy = policy
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
