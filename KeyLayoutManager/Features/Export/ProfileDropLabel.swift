import SwiftUI

struct ProfileDropLabel: View {
    let profile: ProfileLocation
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Label(profile.profileName, systemImage: "person.crop.circle")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }
    }
}
