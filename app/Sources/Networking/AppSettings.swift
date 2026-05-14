import Foundation
import SwiftUI

/// Persisted client-side settings. Backed by `UserDefaults` so they survive
/// relaunches, exposed as `@Observable` so views recompose on change.
@Observable
final class AppSettings {
    static let backendURLKey = "backend.url"

    var backendURL: URL {
        didSet { UserDefaults.standard.set(backendURL.absoluteString, forKey: Self.backendURLKey) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.backendURLKey)
        let fallback = URL(string: "http://82.38.68.48:4400")!
        self.backendURL = stored.flatMap(URL.init(string:)) ?? fallback
    }
}
