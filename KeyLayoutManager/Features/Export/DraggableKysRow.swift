import SwiftUI

struct DraggableKysRow: View {
    let layout: KeyboardLayout
    let stagedURL: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layout.kind.sfSymbol)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(byteString)
                    Text("·")
                    Text(layout.modified, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .draggable(stagedURL) {
            HStack {
                Image(systemName: layout.kind.sfSymbol)
                Text(layout.fileURL.lastPathComponent)
            }
            .padding(6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var byteString: String {
        ByteCountFormatter.string(fromByteCount: layout.byteSize, countStyle: .file)
    }
}
