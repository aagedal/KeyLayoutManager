import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @State private var model = RestoreViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            destinationPicker
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
            Text("Drop .kys files here")
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
            model.add(urls: urls)
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
    private var fileList: some View {
        if model.incomingFiles.isEmpty {
            Text("No files queued yet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Incoming (\(model.incomingFiles.count))")
                    .font(.subheadline.weight(.semibold))
                List {
                    ForEach(model.incomingFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "keyboard")
                            Text(url.lastPathComponent)
                            Spacer()
                            Button {
                                model.remove(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 220)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await model.performRestore() }
            } label: {
                Label("Restore", systemImage: "tray.and.arrow.down.fill")
            }
            .disabled(model.incomingFiles.isEmpty || model.selectedDestination == nil)
            .keyboardShortcut(.return, modifiers: [.command])

            if !model.incomingFiles.isEmpty {
                Button("Clear") { model.clear() }
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
}
