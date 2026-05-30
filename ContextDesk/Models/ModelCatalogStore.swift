import Foundation

/// Disk cache for the discovered model catalog, so the picker shows the latest
/// known models instantly on launch (before any network round-trip) and stays
/// populated while offline. Mirrors `AppPreferencesStore`'s overridable
/// `defaults` seam for unit testing.
enum ModelCatalogStore {
    static var defaults: UserDefaults = .standard
    static let schemaVersion = 1
    private static let key = "ContextDesk.modelCatalog.v1"

    struct Snapshot: Codable {
        var resolved: [ResolvedFamily]
        var derived: [DiscoveredModel]
        var fetchedAt: [String: Date]   // provider rawValue → last success
        var schemaVersion: Int
    }

    static func load() -> Snapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == schemaVersion
        else { return nil }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
