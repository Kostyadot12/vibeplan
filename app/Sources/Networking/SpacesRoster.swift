import Foundation
import SwiftUI

/// Current scope shown in the calendar.
/// `.personal` — only my own personal tasks (creator==me, spaceId==nil).
/// `.space(id)` — tasks belonging to that space.
enum Scope: Hashable {
    case personal
    case space(String)
}

/// Cached list of spaces I'm a member of, plus the current `Scope` selection.
/// Persists scope across launches via UserDefaults so the app reopens to
/// where you left off.
@Observable
final class SpacesRoster {
    private static let scopeKey = "ui.scope"

    @MainActor private(set) var spaces: [SpaceDTO] = []
    @MainActor private(set) var loading: Bool = false
    @MainActor private(set) var lastError: String?
    @MainActor var scope: Scope = .personal {
        didSet { persistScope() }
    }

    private let auth: AuthState
    private let settings: AppSettings

    init(auth: AuthState, settings: AppSettings) {
        self.auth = auth
        self.settings = settings
    }

    /// Apply the saved scope from UserDefaults. Called once at app startup.
    @MainActor
    func restoreScope() {
        guard let raw = UserDefaults.standard.string(forKey: Self.scopeKey) else { return }
        if raw == "personal" {
            scope = .personal
        } else if raw.hasPrefix("space:") {
            scope = .space(String(raw.dropFirst("space:".count)))
        }
    }

    @MainActor
    func refresh() async {
        guard auth.isAuthenticated else { return }
        loading = true; lastError = nil
        defer { loading = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            spaces = try await client.listSpaces()
            // If current scope points to a space we no longer belong to, fall back to personal.
            if case .space(let id) = scope, !spaces.contains(where: { $0.id == id }) {
                scope = .personal
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    @MainActor
    func upsert(_ space: SpaceDTO) {
        if let idx = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[idx] = space
        } else {
            spaces.append(space)
        }
    }

    @MainActor
    func remove(spaceId: String) {
        spaces.removeAll { $0.id == spaceId }
        if case .space(let id) = scope, id == spaceId { scope = .personal }
    }

    @MainActor
    func space(byId id: String) -> SpaceDTO? {
        spaces.first { $0.id == id }
    }

    /// Members of the currently-selected space (empty if scope is .personal).
    @MainActor
    var currentSpaceMembers: [SpaceMemberDTO] {
        guard case .space(let id) = scope, let s = space(byId: id) else { return [] }
        return s.members
    }

    private func persistScope() {
        let raw: String
        switch scope {
        case .personal:        raw = "personal"
        case .space(let id):   raw = "space:\(id)"
        }
        UserDefaults.standard.set(raw, forKey: Self.scopeKey)
    }
}
