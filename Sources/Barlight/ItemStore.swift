import AppKit

/// The last scan, so the panel can open instantly while a fresh scan
/// (about half a second) runs in the background.
@MainActor
final class ItemStore {
    private(set) var items: [MenuBarItem] = []
    /// Called on the main actor after each finished scan.
    var onChange: (() -> Void)?
    private var isScanning = false

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let screens = NSScreen.screens.map(\.frame)
        Task {
            let start = Date()
            let fresh = await Self.scan(screens: screens)
            log.notice("scan: \(fresh.count) items in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            items = fresh
            isScanning = false
            onChange?()
        }
    }

    @concurrent
    private nonisolated static func scan(screens: [CGRect]) async -> [MenuBarItem] {
        ItemScanner.scan(screens: screens)
    }
}
