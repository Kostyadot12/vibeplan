import Foundation
import SwiftUI

/// Cache of tags available in the current scope. Refresh after scope change
/// or after `tag.created/deleted` WS events.
@Observable
final class TagsRoster {
    @MainActor private(set) var tags: [TagDTO] = []
    @MainActor private(set) var loading: Bool = false
    @MainActor private(set) var lastError: String?

    private let auth: AuthState
    private let settings: AppSettings

    init(auth: AuthState, settings: AppSettings) {
        self.auth = auth
        self.settings = settings
    }

    @MainActor
    func refresh(scope: Scope) async {
        guard auth.isAuthenticated else { return }
        loading = true; lastError = nil
        defer { loading = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let spaceId: String? = {
                if case .space(let id) = scope { return id }
                return nil
            }()
            tags = try await client.listTags(spaceId: spaceId)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    @MainActor
    func upsert(_ tag: TagDTO) {
        if let i = tags.firstIndex(where: { $0.id == tag.id }) { tags[i] = tag }
        else { tags.append(tag) }
    }

    @MainActor
    func remove(id: String) {
        tags.removeAll { $0.id == id }
    }
}
