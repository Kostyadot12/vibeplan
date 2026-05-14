import Foundation
import SwiftUI

/// Cached list of team members fetched from `GET /team`.
/// Used by the assignee picker in the task editor.
@Observable
@MainActor
final class TeamRoster {
    private(set) var members: [TeamMemberDTO] = []
    private(set) var loading: Bool = false
    private(set) var lastError: String?

    private let auth: AuthState
    private let settings: AppSettings

    init(auth: AuthState, settings: AppSettings) {
        self.auth = auth
        self.settings = settings
    }

    func refresh() async {
        guard auth.isAuthenticated else { return }
        loading = true; lastError = nil
        defer { loading = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            members = try await client.listTeam()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Look up a member by id; returns a synthetic placeholder if not found
    /// (e.g. user has been removed but still references an old assignee).
    func member(byId id: String) -> TeamMemberDTO? {
        members.first { $0.id == id }
    }
}
