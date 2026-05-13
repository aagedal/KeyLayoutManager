import Foundation

// Collision UX is implemented directly via NSAlert inside RestoreViewModel
// and ExportViewModel so it can suspend `CopyService` via CheckedContinuation
// from inside the copy loop. This file is intentionally a placeholder so the
// pattern is discoverable from the file tree; a SwiftUI `.alert` host would
// also work but doesn't compose as cleanly with the async copy primitive.

enum CollisionAlert {}
