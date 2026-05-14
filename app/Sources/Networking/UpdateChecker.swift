import Foundation
import SwiftUI

/// Lightweight semantic version. Compare via Comparable.
struct SemVer: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    /// Parse "v1.2.3" or "1.2.3". Returns nil for malformed strings.
    init?(_ raw: String) {
        let stripped = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = stripped.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        self.major = parts[0]; self.minor = parts[1]; self.patch = parts[2]
    }

    static func < (a: SemVer, b: SemVer) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        return a.patch < b.patch
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// Description of a release pulled from GitHub.
struct ReleaseInfo: Hashable, Identifiable {
    let version: SemVer
    let tag: String                 // "v0.8.0"
    let name: String                // human-readable name
    let notes: String               // markdown body
    let dmgURL: URL
    let dmgSize: Int64              // bytes
    let publishedAt: Date?

    var id: String { tag }
}

/// Polls the GitHub Releases API and exposes any available update.
@Observable
final class UpdateChecker {
    @MainActor private(set) var current: SemVer
    @MainActor private(set) var available: ReleaseInfo?
    @MainActor private(set) var checking: Bool = false
    @MainActor private(set) var lastCheckedAt: Date?

    private let owner = "Kostyadot12"
    private let repo  = "vibeplan"
    private let pollInterval: TimeInterval = 6 * 60 * 60   // 6 hours
    private var pollTask: Task<Void, Never>?

    init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.current = SemVer(raw) ?? SemVer(0, 0, 0)
    }

    /// Start a background loop that re-checks every `pollInterval`.
    @MainActor
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 21600) * 1_000_000_000))
            }
        }
    }

    @MainActor
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @MainActor
    func checkNow() async {
        checking = true
        defer { checking = false; lastCheckedAt = .now }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
        else { return }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let v = SemVer(tag),
                  let assets = json["assets"] as? [[String: Any]]
            else { return }

            // Only show as "available" if strictly newer than what we are.
            guard v > current else {
                self.available = nil
                return
            }

            // Find the DMG asset. Fall back to first asset if naming differs.
            let dmg = assets.first(where: {
                ($0["name"] as? String)?.hasSuffix(".dmg") == true
            }) ?? assets.first
            guard let dmg,
                  let urlStr = dmg["browser_download_url"] as? String,
                  let dmgURL = URL(string: urlStr)
            else { return }

            let size = (dmg["size"] as? Int64) ?? Int64((dmg["size"] as? Int) ?? 0)
            let name = json["name"] as? String ?? tag
            let body = json["body"] as? String ?? ""
            let publishedAt: Date? = {
                guard let s = json["published_at"] as? String else { return nil }
                let f = ISO8601DateFormatter()
                return f.date(from: s)
            }()

            self.available = ReleaseInfo(
                version: v, tag: tag, name: name, notes: body,
                dmgURL: dmgURL, dmgSize: size, publishedAt: publishedAt
            )
        } catch {
            // Silently ignore; we'll retry on the next poll.
        }
    }
}
