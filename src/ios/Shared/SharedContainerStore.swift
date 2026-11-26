import Foundation

/// Reads and writes PendingShare data to the App Group shared container.
/// Compiled into both the main app target and the Share Extension target.
enum SharedContainerStore {
    static let appGroupID = "group.com.openminis.app"

    /// Name of the fallback directory used when the App Group entitlement is
    /// absent. Deliberately distinctive so a human reading a path dump can tell
    /// the app is running unsandboxed-by-group (that is, in the free-signing
    /// "精简版" build) rather than in the real shared container.
    private static let localGroupDirName = "MinisLocalGroup"

    /// The App Group container, or a stand-in inside the process's own sandbox.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil when
    /// the running binary has no `com.apple.security.application-groups`
    /// entitlement — which is exactly what happens when the app is re-signed
    /// with a free personal team. Every caller used to force-unwrap this, so
    /// such a build died on launch; the paths below (`MinisFileProvider/…`,
    /// `MinisConfig/…`) all derive from it, so one fallback keeps them working.
    ///
    /// Substituting Application Support is not a shared location: the File
    /// Provider, Share and Widget extensions each get their own copy and see
    /// nothing the app writes, and the app sees nothing they write. The main
    /// app — where memory, skills, shared files and the chat database live —
    /// stays fully functional, which is what the fallback is for. When the
    /// entitlement IS present this returns the container verbatim, so App Store
    /// builds are unaffected.
    static var containerURL: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return container
        }
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let url = base.appendingPathComponent(localGroupDirName, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let pendingShareKey = "pendingShare"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Directory in the shared container for transferring attachment files.
    static var sharedFileDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("ShareExtension", isDirectory: true)
    }

    // MARK: - Write (called by Share Extension)

    static func savePendingShare(_ share: PendingShare) {
        guard let defaults = sharedDefaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(share) {
            defaults.set(data, forKey: pendingShareKey)
            defaults.synchronize()
        }
    }

    // MARK: - Read & Consume (called by main app)

    static func loadPendingShare() -> PendingShare? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: pendingShareKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingShare.self, from: data)
    }

    static func clearPendingShare() {
        sharedDefaults?.removeObject(forKey: pendingShareKey)
        sharedDefaults?.synchronize()
    }

    /// Remove all files from the shared transfer directory.
    static func cleanSharedFiles() {
        guard let dir = sharedFileDirectory else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }
}
