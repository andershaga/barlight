import Foundation

/// Ranks items against what the user typed.
enum Matcher {
    /// Matching items, best first. An empty query keeps the given order.
    static func filter(_ items: [MenuBarItem], query: String) -> [MenuBarItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }

        return items.enumerated()
            .compactMap { index, item -> (score: Int, index: Int, item: MenuBarItem)? in
                // The item's own name beats its app's name.
                let score = max(score(item.title.lowercased(), q), score(item.appName.lowercased(), q) - 10)
                return score > 0 ? (score, index, item) : nil
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.item)
    }

    /// 100 prefix, 80 word start, 60 substring, up to 40 for letters in order
    /// ("rp" → "Rectangle Pro"), 0 for no match.
    static func score(_ text: String, _ query: String) -> Int {
        if text.hasPrefix(query) { return 100 }
        let words = text.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(query) }) { return 80 }
        if text.contains(query) { return 60 }

        var cursor = text.startIndex
        var gaps = 0
        for (i, char) in query.enumerated() {
            guard let found = text[cursor...].firstIndex(of: char) else { return 0 }
            if i > 0 { gaps += text.distance(from: cursor, to: found) }
            cursor = text.index(after: found)
        }
        return max(1, 40 - gaps)
    }
}
