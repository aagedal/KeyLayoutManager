import SwiftUI

struct ExportView: View {
    @State private var model = ExportViewModel()

    var body: some View {
        HSplitView {
            sourceList
                .frame(minWidth: 280, idealWidth: 320)
            detail
                .frame(minWidth: 320)
        }
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

    private var sourceList: some View {
        Group {
            if model.installs.isEmpty {
                ContentUnavailableView(
                    "No Premiere Pro profiles",
                    systemImage: "keyboard.badge.ellipsis",
                    description: Text("Premiere Pro doesn't seem to be installed for this user, or the Documents folder is empty.")
                )
            } else {
                List(selection: $model.selection) {
                    ForEach(model.installs) { install in
                        Section(PremiereProduct.displayName(forVersion: install.version)) {
                            ForEach(install.profiles) { profile in
                                profileSection(profile)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private func profileSection(_ profile: ProfileLocation) -> some View {
        let layouts = model.items(for: profile, kind: .kys)
        let presets = model.items(for: profile, kind: .sourcePatcher)
        let workspaces = model.items(for: profile, kind: .workspace)
        DisclosureGroup {
            if layouts.isEmpty && presets.isEmpty && workspaces.isEmpty {
                Text("(no items — drop .kys, .sppreset, or panel layout .xml files here to copy in)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                kindSubsection(title: "Keyboard Layouts", items: layouts)
                kindSubsection(title: "Source Assignment Presets", items: presets)
                kindSubsection(title: "Panel Layouts", items: workspaces)
            }
        } label: {
            ProfileDropLabel(profile: profile) { urls in
                Task { await model.dropOnProfile(urls: urls, profile: profile) }
            }
            .contextMenu {
                Button {
                    Task { await model.backupProfile(profile) }
                } label: {
                    Label("Back Up Profile…", systemImage: "archivebox")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await model.deleteProfile(profile) }
                } label: {
                    Label("Delete Profile…", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func kindSubsection(title: String, items: [KeyboardLayout]) -> some View {
        if !items.isEmpty {
            Text("\(title) (\(items.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            ForEach(items) { item in
                DraggableKysRow(layout: item,
                                stagedURL: model.stagedURL(for: item))
                    .tag(item.fileURL)
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.selectedItems.isEmpty {
                ContentUnavailableView(
                    "Select items to export",
                    systemImage: "hand.point.up.left",
                    description: Text("Pick keyboard layouts, source assignment presets, or panel layouts on the left, then drag them out or export below.")
                )
            } else {
                Text("Selected (\(model.selectedItems.count))")
                    .font(.headline)
                ForEach(model.selectedItems) { item in
                    HStack {
                        Image(systemName: item.kind.sfSymbol)
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                            Text(item.fileURL.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        Task { await model.exportToFolder() }
                    } label: {
                        Label("Export to…", systemImage: "square.and.arrow.up")
                    }

                    if model.iCloudURL != nil {
                        Button {
                            Task { await model.backupToICloud() }
                        } label: {
                            Label("Backup to iCloud", systemImage: "icloud.and.arrow.up")
                        }
                    }

                    if model.dropboxURL != nil {
                        Button {
                            Task { await model.backupToDropbox() }
                        } label: {
                            Label("Backup to Dropbox", systemImage: "shippingbox")
                        }
                    }

                    Spacer()
                }

                Text("Tip: drag any selected item out of the list into Slack, Mail, or Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = model.statusMessage {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.green)
                }
                if let err = model.errorMessage {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding()
    }
}
