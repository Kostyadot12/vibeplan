import SwiftUI
import SwiftData

/// Shared session-scoped drag state. SwiftUI's `.onDrag` fires before the drop,
/// so we stash the dragged task here and read it from drop handlers across the
/// view tree. Avoids the boilerplate of building Transferable wrappers for
/// SwiftData PersistentIdentifier values.
@Observable
final class DragState {
    var dragged: PlanTask?
}
