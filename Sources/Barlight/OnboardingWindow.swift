import AppKit

/// First-run window: explains why Barlight needs Accessibility, opens the
/// right Settings pane, and notices the moment access is granted.
@MainActor
final class OnboardingWindowController: NSWindowController {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!

    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)
    private var pollTimer: Timer?
    private static let width: CGFloat = 460
    private static let margin: CGFloat = 36

    private let hotkey: String
    private let onGranted: () -> Void
    /// After Done: hand over to Settings so the hotkey can be chosen.
    private let onFinish: () -> Void

    init(hotkey: String, onGranted: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onGranted = onGranted
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: true
        )
        window.title = "Welcome to Barlight"
        super.init(window: window)

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let heading = NSTextField(labelWithString: "Allow Accessibility access")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let textWidth = Self.width - 2 * Self.margin
        let body = NSTextField(wrappingLabelWithString: "Barlight reads the names of your menu bar items and opens their menus through Accessibility. It doesn't read anything else.\n\nTurn on Barlight in Privacy & Security › Accessibility. This window updates once access is granted.")
        body.alignment = .center
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = textWidth
        body.widthAnchor.constraint(equalToConstant: textWidth).isActive = true

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        actionButton.target = self
        actionButton.action = #selector(performAction)
        actionButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, heading, body, statusLabel, actionButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(18, after: body)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: Self.margin, bottom: 24, right: Self.margin)
        // Pin the width so the wrapping text keeps its margins.
        stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        window.contentView = stack
        window.setContentSize(NSSize(width: Self.width, height: stack.fittingSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        updateState()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateState() }
        }
    }

    private var isGranted: Bool { AXIsProcessTrusted() }

    private func updateState() {
        if isGranted {
            pollTimer?.invalidate()
            pollTimer = nil
            statusLabel.stringValue = "Access granted. Press \(hotkey) anywhere to search your menu bar."
            statusLabel.textColor = .systemGreen
            actionButton.title = "Done"
            onGranted()
        } else {
            statusLabel.stringValue = "Waiting for access…"
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "Open Accessibility Settings"
        }
    }

    @objc private func performAction() {
        if isGranted {
            close()
            onFinish()
            return
        }
        // Asking once puts Barlight in the Accessibility list, ready to switch on.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        NSWorkspace.shared.open(Self.settingsURL)
    }
}
