import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class RestoreViewModel {
    var isRestoring = false
    var incomingItems: [IncomingItem] = []
    var loadedBackupManifest: BackupManifest?
    var loadedBackupSourceLabel: String?
    var destinations: [ProfileLocation] = []
    var selectedDestination: ProfileLocation?
    var iCloudURL: URL?
    var dropboxURL: URL?
    var statusMessage: String?
    var errorMessage: String?

    private let scanner: PremiereScanner
    private let copier = CopyService()
    private let zipService = ZipService()
    private let fm = FileManager.default

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

    func kind(of url: URL) -> PremiereItemKind? {
        PremiereItemKind.kind(forFileExtension: url.pathExtension)
    }

    var selectedCount: Int {
        incomingItems.filter(\.isSelected).count
    }

    var hasZipBackup: Bool {
        incomingItems.contains { if case .zipEntry = $0.source { return true } else { return false } }
    }

    var groupedItems: [(group: String, items: [IncomingItem])] {
        let ordered = incomingItems.reduce(into: [String: [IncomingItem]]()) { acc, item in
            acc[item.topLevelGroup, default: []].append(item)
        }
        let groupOrder = incomingItems.map(\.topLevelGroup).reduce(into: [String]()) { acc, name in
            if !acc.contains(name) { acc.append(name) }
        }
        return groupOrder.map { ($0, ordered[$0] ?? []) }
    }

    func add(urls: [URL]) async {
        for url in urls {
            await addOne(url)
        }
    }

    private func addOne(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            await loadZip(url)
            return
        }
        guard let kind = PremiereItemKind.kind(forFileExtension: ext) else { return }
        let item = IncomingItem.looseFile(url: url, kind: kind)
        if !incomingItems.contains(where: { sameSource($0, item) }) {
            incomingItems.append(item)
        }
    }

    private func loadZip(_ zipURL: URL) async {
        do {
            let entries = try await zipService.listEntries(zip: zipURL)
            let manifest = await zipService.readManifest(zip: zipURL)

            let interestingEntries = entries.filter { entry in
                !entry.isDirectory && entry.path != ZipService.manifestFilename
            }

            for entry in interestingEntries {
                let item = IncomingItem.zipEntry(zipURL: zipURL, entryPath: entry.path)
                if !incomingItems.contains(where: { sameSource($0, item) }) {
                    incomingItems.append(item)
                }
            }

            if loadedBackupManifest == nil {
                loadedBackupManifest = manifest
                loadedBackupSourceLabel = manifest != nil ? nil : zipURL.lastPathComponent
            }
        } catch {
            errorMessage = "Couldn't read \(zipURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func sameSource(_ a: IncomingItem, _ b: IncomingItem) -> Bool {
        switch (a.source, b.source) {
        case let (.looseFile(u1), .looseFile(u2)):
            return u1 == u2
        case let (.zipEntry(z1, e1), .zipEntry(z2, e2)):
            return z1 == z2 && e1 == e2
        default:
            return false
        }
    }

    func remove(id: UUID) {
        incomingItems.removeAll { $0.id == id }
        if incomingItems.allSatisfy({ if case .zipEntry = $0.source { return false } else { return true } }) {
            loadedBackupManifest = nil
            loadedBackupSourceLabel = nil
        }
    }

    func toggle(id: UUID) {
        guard let idx = incomingItems.firstIndex(where: { $0.id == id }) else { return }
        incomingItems[idx].isSelected.toggle()
    }

    func setSelection(_ selected: Bool, in group: String) {
        for idx in incomingItems.indices where incomingItems[idx].topLevelGroup == group {
            incomingItems[idx].isSelected = selected
        }
    }

    func setAllSelected(_ selected: Bool) {
        for idx in incomingItems.indices {
            incomingItems[idx].isSelected = selected
        }
    }

    func groupSelectionState(_ group: String) -> GroupSelection {
        let items = incomingItems.filter { $0.topLevelGroup == group }
        let selected = items.filter(\.isSelected).count
        if selected == 0 { return .none }
        if selected == items.count { return .all }
        return .partial
    }

    enum GroupSelection {
        case none, partial, all
    }

    func clear() {
        incomingItems.removeAll()
        loadedBackupManifest = nil
        loadedBackupSourceLabel = nil
        statusMessage = nil
        errorMessage = nil
    }

    func chooseFiles() {
        runChooser(startingAt: nil, message: "Choose .kys / .sppreset files or a backup .zip to restore.")
    }

    func chooseFromICloud() {
        guard let root = iCloudURL else { return }
        let backupRoot = root.appendingPathComponent(CloudTargets.backupSubfolder, isDirectory: true)
        let startURL = FileManager.default.fileExists(atPath: backupRoot.path) ? backupRoot : root
        runChooser(startingAt: startURL,
                   message: "Pick .kys / .sppreset files or a backup .zip from iCloud Drive.")
    }

    func chooseFromDropbox() {
        guard let root = dropboxURL else { return }
        let backupRoot = root.appendingPathComponent(CloudTargets.backupSubfolder, isDirectory: true)
        let startURL = FileManager.default.fileExists(atPath: backupRoot.path) ? backupRoot : root
        runChooser(startingAt: startURL,
                   message: "Pick .kys / .sppreset files or a backup .zip from Dropbox.")
    }

    private func runChooser(startingAt directoryURL: URL?, message: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types = PremiereItemKind.allCases.compactMap { UTType(filenameExtension: $0.fileExtension) }
        if let zipType = UTType("public.zip-archive") {
            types.append(zipType)
        }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        if let directoryURL { panel.directoryURL = directoryURL }
        panel.prompt = "Add"
        panel.message = message
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await self.add(urls: urls) }
        }
    }

    func performRestore() async {
        guard !isRestoring else { return }
        let selected = incomingItems.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        guard let dest = selectedDestination else {
            errorMessage = "Pick a destination profile."
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        statusMessage = nil
        errorMessage = nil
        applyToAllPolicy = nil

        var stagingDirs: [URL] = []
        defer {
            for dir in stagingDirs { try? fm.removeItem(at: dir) }
        }

        var extractedByID: [UUID: URL] = [:]
        var zipBuckets: [URL: [IncomingItem]] = [:]
        for item in selected {
            if case .zipEntry(let zipURL, _) = item.source {
                zipBuckets[zipURL, default: []].append(item)
            }
        }

        for (zipURL, items) in zipBuckets {
            let stagingDir = fm.temporaryDirectory
                .appendingPathComponent("KeyLayoutManager-restore-\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                stagingDirs.append(stagingDir)
                let paths = items.compactMap { item -> String? in
                    if case .zipEntry(_, let entryPath) = item.source { return entryPath } else { return nil }
                }
                let extracted = try await zipService.extract(entries: paths, from: zipURL, into: stagingDir)
                for item in items {
                    if case .zipEntry(_, let entryPath) = item.source,
                       let url = extracted[entryPath] {
                        extractedByID[item.id] = url
                    }
                }
            } catch {
                errorMessage = "Couldn't extract \(zipURL.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }

        var completedIDs: Set<UUID> = []
        var failures: [String] = []
        var copied = 0
        var renamed = 0
        var skipped = 0

        for item in selected {
            let sourceURL: URL
            switch item.source {
            case .looseFile(let url):
                sourceURL = url
            case .zipEntry:
                guard let url = extractedByID[item.id] else { continue }
                sourceURL = url
            }

            let destinationDir: URL = {
                let parent = item.parentRelativePath
                if parent.isEmpty {
                    return dest.profileRootURL
                }
                return parent.split(separator: "/").reduce(dest.profileRootURL) { acc, comp in
                    acc.appendingPathComponent(String(comp), isDirectory: true)
                }
            }()

            let policy: CollisionPolicy = applyToAllPolicy ?? .prompt
            do {
                let outcome = try await copier.copy(sourceURL, into: destinationDir, policy: policy) { [weak self] target in
                    guard let self else { return .skip }
                    let result = await self.promptCollision(targetURL: target)
                    if result.applyToAll { await self.setApplyToAll(result.policy) }
                    return result.policy
                }
                switch outcome {
                case .copied: copied += 1; completedIDs.insert(item.id)
                case .renamed: renamed += 1; completedIDs.insert(item.id)
                case .skipped: skipped += 1
                }
            } catch {
                failures.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        statusMessage = summary(copied: copied, renamed: renamed, skipped: skipped, dest: dest)
        for id in completedIDs { remove(id: id) }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func summary(copied: Int, renamed: Int, skipped: Int, dest: ProfileLocation) -> String {
        var parts: [String] = []
        if copied > 0 { parts.append("\(copied) copied") }
        if renamed > 0 { parts.append("\(renamed) renamed") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        let body = parts.isEmpty ? "Nothing to do" : parts.joined(separator: ", ")
        return "\(body) → \(dest.displayName)"
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
