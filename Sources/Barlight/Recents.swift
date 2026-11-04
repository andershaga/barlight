import Foundation

/// Which items the user opens, so frequent ones rise to the top.
enum Recents {
    private struct Usage: Codable {
        var count: Int
        var lastUsed: Date
    }

    private static let defaultsKey = "recents"
    /// Uses older than this no longer lift an item.
    private static let horizon: TimeInterval = 30 * 24 * 3600

    /// Stable across name changes where possible: the AX identifier, else the title.
    private static func key(_ item: MenuBarItem) -> String {
        "\(item.bundleID ?? item.appName)|\(item.axIdentifier ?? item.title)"
    }

    static func record(_ item: MenuBarItem) {
        var usage = load()
        let key = key(item)
        usage[key] = Usage(count: (usage[key]?.count ?? 0) + 1, lastUsed: Date())
        UserDefaults.standard.set(try? JSONEncoder().encode(usage), forKey: defaultsKey)
    }

    /// Frecency for each item, 0 when unused: more uses and more recent
    /// use both score higher.
    static func scores(for items: [MenuBarItem]) -> [Int] {
        let usage = load()
        let now = Date()
        return items.map { item in
            guard let use = usage[key(item)] else { return 0 }
            let age = now.timeIntervalSince(use.lastUsed)
            guard age < horizon else { return 0 }
            let recency = age < 3600 ? 4 : age < 86400 ? 3 : age < 7 * 86400 ? 2 : 1
            return min(use.count, 10) * recency
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func load() -> [String: Usage] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let usage = try? JSONDecoder().decode([String: Usage].self, from: data)
        else { return [:] }
        return usage
    }
}
