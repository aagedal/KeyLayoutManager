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
                        Section(install.version) {
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
        let layouts = model.allLayouts.filter { $0.origin.id == profile.id }
        DisclosureGroup {
            if layouts.isEmpty {
                Text("(no .kys files — drop here to copy in)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(layouts) { layout in
                    DraggableKysRow(layout: layout,
                                    stagedURL: model.stagedURL(for: layout))
                        .tag(layout.fileURL)
                }
            }
        } label: {
            ProfileDropLabel(profile: profile) { urls in
                Task { await model.dropOnProfile(urls: urls, profile: profile) }
            }
            .contextMenu {
                Button(role: .destructive) {
                    Task { await model.deleteProfile(profile) }
                } label: {
                    Label("Delete Profile…", systemImage: "trash")
                }
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.selectedLayouts.isEmpty {
                ContentUnavailableView(
                    "Select keyboard layouts",
                    systemImage: "hand.point.up.left",
                    description: Text("Pick one or more .kys files on the left, then drag them out or export below.")
                )
            } else {
                Text("Selected (\(model.selectedLayouts.count))")
                    .font(.headline)
                ForEach(model.selectedLayouts) { layout in
                    HStack {
                        Image(systemName: "keyboard")
                        VStack(alignment: .leading) {
                            Text(layout.displayName)
                            Text(layout.fileURL.path)
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

                Text("Tip: drag any selected file out of the list into Slack, Mail, or Finder.")
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
