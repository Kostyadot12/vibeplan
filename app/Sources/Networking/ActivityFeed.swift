import Foundation
import SwiftUI

/// Cached recent activity for the current scope.
@Observable
final class ActivityFeed {
    @MainActor private(set) var events: [ActivityEventDTO] = []
    @MainActor private(set) var loading: Bool = false

    private let auth: AuthState
    private let settings: AppSettings

    init(auth: AuthState, settings: AppSettings) {
        self.auth = auth
        self.settings = settings
    }

    @MainActor
    func refresh(scope: Scope) async {
        guard auth.isAuthenticated else { return }
        loading = true; defer { loading = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let sid: String? = {
                if case .space(let id) = scope { return id }
                return nil
            }()
            events = try await client.listActivity(spaceId: sid)
        } catch {
            // Best-effort; ignore for now
        }
    }
}
