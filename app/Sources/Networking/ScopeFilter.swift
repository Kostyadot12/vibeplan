import Foundation

/// Returns true iff the task should be visible under the given scope.
/// - .personal: spaceServerId == nil (i.e. not part of any shared space).
/// - .space(id): spaceServerId == id.
func matchesScope(_ task: PlanTask, scope: Scope) -> Bool {
    switch scope {
    case .personal:
        return task.spaceServerId == nil
    case .space(let id):
        return task.spaceServerId == id
    }
}
