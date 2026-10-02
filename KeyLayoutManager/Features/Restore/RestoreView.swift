import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @State private var model = RestoreViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            destinationPicker
            backupBanner
            fileList
            actions
            Spacer()
        }
        .padding()
        .onAppear { model.refresh() }
        .toolbar {
            ToolbarItem {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Drop .kys, .sppreset, panel layout .xml, or a backup .zip here")
                .font(.headline)
            HStack(spacing: 8) {
                Button {
                    model.chooseFiles()
                } label: {
                    Label("Choose files…", systemImage: "folder")
                }
                if model.iCloudURL != nil {
                    Button {
                        model.chooseFromICloud()
                    } label: {
                        Label("From iCloud…", systemImage: "icloud")
                    }
                }
                if model.dropboxURL != nil {
                    Button {
                        model.chooseFromDropbox()
                    } label: {
                        Label("From Dropbox…", systemImage: "shippingbox")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isDropTargeted ? .blue : .secondary)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.blue.opacity(0.08) : Color.clear)
        )
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.add(urls: urls) }
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    @ViewBuilder
    private var destinationPicker: some View {
        if model.destinations.isEmpty {
            Label("No Premiere Pro profiles found on this Mac.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            HStack {
                Text("Restore to:")
                Picker("", selection: Binding(
                    get: { model.selectedDestination?.id ?? "" },
                    set: { newID in
                        model.selectedDestination = model.destinations.first { $0.id == newID }
                    }
                )) {
                    ForEach(model.destinations) { dest in
                        Text(dest.displayName).tag(dest.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var backupBanner: some View {
        if let manifest = model.loadedBackupManifest {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.blue)
                Text("Backup of \(PremiereProduct.displayName(forVersion: manifest.sourceVersion)) — \(manifest.sourceProfileName)")
                    .font(.subheadline.weight(.medium))
                Text(manifest.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
        } else if let label = model.loadedBackupSourceLabel {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.orange)
                Text("\(label) — no KeyLayoutManager manifest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if model.incomingItems.isEmpty {
            Text("No files queued yet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Incoming (\(model.incomingItems.count))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Select all") { model.setAllSelected(true) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Button("Select none") { model.setAllSelected(false) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                List {
                    ForEach(model.groupedItems, id: \.group) { group in
                        Section {
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
                        } header: {
                            groupHeader(name: group.group)
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 320)
            }
        }
    }

    private func groupHeader(name: String) -> some View {
        let state = model.groupSelectionState(name)
        return HStack(spacing: 6) {
            Button {
                model.setSelection(state != .all, in: name)
            } label: {
                Image(systemName: checkboxSymbol(for: state))
                    .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            Text(name)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func itemRow(_ item: IncomingItem) -> some View {
        HStack(spacing: 6) {
            Button {
                model.toggle(id: item.id)
            } label: {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            Image(systemName: item.kindHint?.sfSymbol ?? "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                if item.relativePath != item.displayName {
                    Text(item.relativePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.remove(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .helpIfPresent(PremiereFileInfo.description(for: item.relativePath))
    }

    private func checkboxSymbol(for state: RestoreViewModel.GroupSelection) -> String {
        switch state {
        case .none: return "square"
        case .partial: return "minus.square.fill"
        case .all: return "checkmark.square.fill"
        }
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await model.performRestore() }
            } label: {
                Label(restoreLabel, systemImage: "tray.and.arrow.down.fill")
            }
            .disabled(model.isRestoring || model.selectedCount == 0 || model.selectedDestination == nil)
            .keyboardShortcut(.return, modifiers: [.command])

            if !model.incomingItems.isEmpty {
                Button("Clear") { model.clear() }.disabled(model.isRestoring)
            }
            Spacer()
            if let status = model.statusMessage {
                Text(status).font(.callout).foregroundStyle(.green)
            }
            if let err = model.errorMessage {
                Text(err).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var restoreLabel: String {
        let n = model.selectedCount
        if n == 0 { return "Restore" }
        if n == 1 { return "Restore 1 item" }
        return "Restore \(n) items"
    }
}

private extension View {
    @ViewBuilder
    func helpIfPresent(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            self.help(text)
        } else {
            self
        }
    }
}
