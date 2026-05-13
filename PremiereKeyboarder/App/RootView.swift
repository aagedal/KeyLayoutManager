import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case export
    case restore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .export: return "Export"
        case .restore: return "Restore"
        }
    }

    var systemImage: String {
        switch self {
        case .export: return "square.and.arrow.up.on.square"
        case .restore: return "square.and.arrow.down.on.square"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarItem = .export

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ExportView().navigationTitle("Export")
            }
            .tabItem { Label(SidebarItem.export.title, systemImage: SidebarItem.export.systemImage) }
            .tag(SidebarItem.export)

            NavigationStack {
                RestoreView().navigationTitle("Restore")
            }
            .tabItem { Label(SidebarItem.restore.title, systemImage: SidebarItem.restore.systemImage) }
            .tag(SidebarItem.restore)
        }
    }
}
