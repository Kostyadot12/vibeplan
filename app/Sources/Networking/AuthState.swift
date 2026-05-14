import Foundation
import SwiftUI

/// Holds the JWT and the currently-logged-in user. Persisted via Keychain
/// (token) + UserDefaults (user id/email/name/role).
@Observable
final class AuthState {
    private static let userKey = "auth.user.json"

    var token: String?
    var user:  UserDTO?

    var isAuthenticated: Bool { token != nil && user != nil }

    init() {
        self.token = Keychain.loadToken()
        self.user  = Self.loadUser()
    }

    func setLoggedIn(token: String, user: UserDTO) {
        self.token = token
        self.user  = user
        Keychain.saveToken(token)
        Self.saveUser(user)
    }

    func logout() {
        Keychain.deleteToken()
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        token = nil
        user  = nil
    }

    func client(baseURL: URL) -> APIClient {
        APIClient(baseURL: baseURL, token: token)
    }

    // MARK: – Persistence helpers

    private static func saveUser(_ user: UserDTO) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: userKey)
    }

    private static func loadUser() -> UserDTO? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        return try? JSONDecoder().decode(UserDTO.self, from: data)
    }
}
