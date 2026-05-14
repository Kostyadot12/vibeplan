import Foundation
import AppKit

/// Downloads the new DMG, mounts it, and spawns a shell helper that swaps
/// /Applications/VibePlan.app and relaunches. Then we exit ourselves.
///
/// Why a shell helper instead of doing it in-process: macOS prevents you
/// from overwriting a running app's bundle. The helper waits for our
/// process to die, then replaces and relaunches.
@Observable
@MainActor
final class Updater {
    enum State: Equatable {
        case idle
        case downloading(progress: Double)   // 0…1
        case installing
        case failed(String)
    }

    @MainActor private(set) var state: State = .idle

    private var observation: NSKeyValueObservation?

    func install(_ release: ReleaseInfo) async {
        state = .downloading(progress: 0)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibePlan-\(release.tag).dmg")
        if FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.removeItem(at: tmp)
        }

        do {
            try await download(from: release.dmgURL, to: tmp)
        } catch {
            state = .failed("Не удалось скачать обновление: \(error.localizedDescription)")
            return
        }

        state = .installing

        do {
            let mountPoint = try mountDMG(at: tmp)
            try spawnInstallerHelper(mountPoint: mountPoint, dmgPath: tmp)
            // Give the helper a moment to start its `sleep 2`, then exit.
            try? await Task.sleep(nanoseconds: 400_000_000)
            NSApp.terminate(nil)
        } catch {
            state = .failed("Не удалось установить обновление: \(error.localizedDescription)")
        }
    }

    // MARK: – Download with progress

    private func download(from remote: URL, to dest: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: remote) { tempURL, _, error in
                if let error { cont.resume(throwing: error); return }
                guard let tempURL else {
                    cont.resume(throwing: NSError(domain: "Updater", code: -1))
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let v = p.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: v)
                }
            }
            task.resume()
        }
    }

    // MARK: – Mount DMG

    /// Uses `hdiutil attach -plist -nobrowse <dmg>` and parses the plist
    /// to find the actual mount-point — it can be /Volumes/VibePlan or
    /// /Volumes/VibePlan-1 if a stale mount already exists.
    private func mountDMG(at dmg: URL) throws -> String {
        let proc = Process()
        proc.launchPath = "/usr/bin/hdiutil"
        proc.arguments = ["attach", "-plist", "-nobrowse", "-noverify", dmg.path]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "Updater.mount", code: Int(proc.terminationStatus))
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { throw NSError(domain: "Updater.mount", code: -2) }

        for e in entities {
            if let mp = e["mount-point"] as? String, !mp.isEmpty {
                return mp
            }
        }
        throw NSError(domain: "Updater.mount", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Не нашёл точку монтирования в выводе hdiutil"])
    }

    // MARK: – Helper script

    private func spawnInstallerHelper(mountPoint: String, dmgPath: URL) throws {
        // The helper:
        //   1. Wait for us to quit
        //   2. Replace /Applications/VibePlan.app
        //   3. Strip quarantine attribute (Gatekeeper otherwise re-prompts)
        //   4. Detach the DMG
        //   5. Relaunch the new app
        let script = """
        sleep 2
        rm -rf "/Applications/VibePlan.app" 2>/dev/null
        cp -R "\(mountPoint)/VibePlan.app" "/Applications/"
        /usr/bin/xattr -dr com.apple.quarantine "/Applications/VibePlan.app" 2>/dev/null
        /usr/bin/hdiutil detach "\(mountPoint)" -force 2>/dev/null
        rm -f "\(dmgPath.path)" 2>/dev/null
        /usr/bin/open "/Applications/VibePlan.app"
        """

        let proc = Process()
        proc.launchPath = "/bin/bash"
        proc.arguments = ["-c", script]
        // Detach so it survives our exit. NSTask doesn't have a "detach" flag
        // but launching it without setting standardInput/Output and not
        // calling waitUntilExit is enough — the process becomes our child
        // but stays alive after we terminate.
        try proc.run()
    }
}
