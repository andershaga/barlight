import AppKit

/// A button that records the next key combo pressed after it is clicked.
///
/// Esc cancels. The owner must pause the live hotkey while recording, since
/// Carbon hotkeys fire before the key ever reaches this window.
@MainActor
final class HotkeyRecorder: NSButton {
    var combo: HotkeyCombo { didSet { refreshTitle() } }
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecord: ((HotkeyCombo) -> Void)?

    private var monitor: Any?
    private var isRecording = false { didSet { refreshTitle() } }

    init(combo: HotkeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.stopRecording()
            } else if let combo = HotkeyCombo(event: event) {
                self.stopRecording()
                self.onRecord?(combo)
            } else {
                NSSound.beep() // needs ⌘, ⌥ or ⌃
            }
            return nil
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecordingChanged?(false)
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : combo.displayString
    }
}

/// The Settings window: currently just the search hotkey.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let recorder: HotkeyRecorder
    private let statusLabel = NSTextField(labelWithString: "")
    /// Tries to register combo; returns false when the system refuses it.
    private let apply: (HotkeyCombo) -> Bool
    private let setPaused: (Bool) -> Void

    init(current: HotkeyCombo, apply: @escaping (HotkeyCombo) -> Bool, setPaused: @escaping (Bool) -> Void) {
        self.apply = apply
        self.setPaused = setPaused
        recorder = HotkeyRecorder(combo: current)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: true
        )
        window.title = "Barlight Settings"
        super.init(window: window)
        window.delegate = self

        recorder.onRecordingChanged = { [weak self] recording in
            self?.statusLabel.stringValue = recording ? "Press the new shortcut, or Esc to cancel." : ""
            self?.setPaused(recording)
        }
        recorder.onRecord = { [weak self] combo in self?.choose(combo) }

        let reset = NSButton(title: "Reset to \(HotkeyCombo.defaultSearch.displayString)", target: self, action: #selector(resetToDefault))
        reset.bezelStyle = .push

        let label = NSTextField(labelWithString: "Search hotkey:")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let row = NSStackView(views: [label, recorder, reset])
        row.spacing = 8

        let systemToggle = NSButton(
            checkboxWithTitle: "Show system items (Clock, Wi‑Fi, Sound…)",
            target: self, action: #selector(toggleSystemItems(_:))
        )
        systemToggle.state = Preferences.includeSystemItems ? .on : .off

        let stack = NSStackView(views: [row, statusLabel, systemToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        window.contentView = stack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // Wait for the status menu to finish closing; activating while it
        // still tracks leaves the window behind the frontmost app.
        DispatchQueue.main.async { [self] in
            // The cooperative NSApp.activate() is routinely refused for an
            // accessory app while another app is active, so force it.
            NSApp.activate(ignoringOtherApps: true)
            if window?.isVisible == false { window?.center() }
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    @objc private func toggleSystemItems(_ sender: NSButton) {
        Preferences.includeSystemItems = sender.state == .on
    }

    @objc private func resetToDefault() {
        recorder.stopRecording()
        choose(.defaultSearch)
    }

    private func choose(_ combo: HotkeyCombo) {
        if apply(combo) {
            recorder.combo = combo
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "Saved."
        } else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "\(combo.displayString) is taken by the system or another app."
        }
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
    }
}
