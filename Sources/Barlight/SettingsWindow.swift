import AppKit
import ServiceManagement

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

/// The Settings window: hotkey, which items to list, and how to find hidden ones.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let hotkeyHint = "Opens Barlight from any app."
    private static let descriptionWidth: CGFloat = 340

    private let recorder: HotkeyRecorder
    private let hotkeyNote = SettingsWindowController.description(SettingsWindowController.hotkeyHint)
    private let modeNote = SettingsWindowController.description("")
    private let memoryNote = SettingsWindowController.description("")
    private let clearButton = NSButton(title: "Clear Memory", target: nil, action: nil)
    private let loginToggle = NSButton(checkboxWithTitle: "Open Barlight at login", target: nil, action: nil)
    private let loginNote = SettingsWindowController.description("")
    /// Hidden in Reveal mode, where nothing is remembered.
    private var memoryRow: NSGridRow?
    /// Tries to register combo; returns false when the system refuses it.
    private let apply: (HotkeyCombo) -> Bool
    private let setPaused: (Bool) -> Void
    private let store: ItemStore

    init(current: HotkeyCombo, store: ItemStore, apply: @escaping (HotkeyCombo) -> Bool, setPaused: @escaping (Bool) -> Void) {
        self.apply = apply
        self.setPaused = setPaused
        self.store = store
        recorder = HotkeyRecorder(combo: current)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: true
        )
        window.title = "Barlight Settings"
        super.init(window: window)
        window.delegate = self

        // Hotkey
        recorder.onRecordingChanged = { [weak self] recording in
            self?.showHotkeyNote(recording ? "Press the new shortcut, or Esc to cancel." : Self.hotkeyHint)
            self?.setPaused(recording)
        }
        recorder.onRecord = { [weak self] combo in self?.choose(combo) }
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let reset = NSButton(title: "Reset to \(HotkeyCombo.defaultSearch.displayString)", target: self, action: #selector(resetToDefault))
        let hotkeyControls = NSStackView(views: [recorder, reset])
        hotkeyControls.spacing = 8

        // System items
        let systemToggle = NSButton(checkboxWithTitle: "Show system items", target: self, action: #selector(toggleSystemItems(_:)))
        systemToggle.state = Preferences.includeSystemItems ? .on : .off
        let systemNote = Self.description("Clock, Wi‑Fi, Sound, input language and other items from Apple.")

        // Hidden items
        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in HiddenItemsMode.allCases {
            modePopup.addItem(withTitle: mode.title)
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        modePopup.selectItem(at: HiddenItemsMode.allCases.firstIndex(of: Preferences.hiddenItemsMode) ?? 0)
        modePopup.target = self
        modePopup.action = #selector(changeHiddenItemsMode(_:))

        clearButton.target = self
        clearButton.action = #selector(clearMemory)
        let memoryControls = NSStackView(views: [clearButton, memoryNote])
        memoryControls.spacing = 10

        // Startup
        loginToggle.target = self
        loginToggle.action = #selector(toggleLaunchAtLogin(_:))

        let grid = NSGridView(views: [
            [Self.label("Search hotkey:"), hotkeyControls],
            [NSGridCell.emptyContentView, hotkeyNote],
            [Self.label("Startup:"), loginToggle],
            [NSGridCell.emptyContentView, loginNote],
            [Self.label("Menu bar:"), systemToggle],
            [NSGridCell.emptyContentView, systemNote],
            [Self.label("Items behind »:"), modePopup],
            [NSGridCell.emptyContentView, modeNote],
            [NSGridCell.emptyContentView, memoryControls],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 6
        // Breathing room between the groups.
        for row in [2, 4, 6] { grid.row(at: row).topPadding = 14 }
        grid.row(at: 8).topPadding = 4
        memoryRow = grid.row(at: 8)

        let content = NSStackView(views: [grid])
        content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        window.contentView = content
        updateHiddenItemsSection()
        window.setContentSize(content.fittingSize)
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private static func description(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = descriptionWidth
        field.widthAnchor.constraint(equalToConstant: descriptionWidth).isActive = true
        return field
    }

    private func showHotkeyNote(_ text: String, isError: Bool = false) {
        hotkeyNote.stringValue = text
        hotkeyNote.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    /// Mode description, plus the memory controls that only apply to Remember.
    private func updateHiddenItemsSection() {
        switch Preferences.hiddenItemsMode {
        case .remember:
            modeNote.stringValue = "Barlight saves each item while it is visible and keeps listing it after macOS moves it behind ». Instant and invisible, but an item must have been visible once. Memory updates every time Barlight opens."
        case .reveal:
            modeNote.stringValue = "Each time Barlight opens it briefly opens » to read the hidden items, then closes it. Always complete and current, with a short flicker. Nothing is saved."
        }
        let isRemember = Preferences.hiddenItemsMode == .remember
        clearButton.isEnabled = isRemember && store.rememberedCount > 0
        let count = store.rememberedCount
        memoryNote.stringValue = count == 1 ? "1 item remembered" : "\(count) items remembered"
        memoryRow?.isHidden = !isRemember
        window?.setContentSize(window?.contentView?.fittingSize ?? .zero)
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
            updateHiddenItemsSection()
            updateLoginSection()
            if window?.isVisible == false { window?.center() }
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    @objc private func changeHiddenItemsMode(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = HiddenItemsMode(rawValue: raw)
        else { return }
        Preferences.hiddenItemsMode = mode
        updateHiddenItemsSection()
    }

    /// Reads the real login-item state, which the user can also change in
    /// System Settings › General › Login Items.
    private func updateLoginSection() {
        let status = SMAppService.mainApp.status
        loginToggle.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginNote.stringValue = status == .requiresApproval
            ? "Waiting for approval in System Settings › General › Login Items."
            : "Starts Barlight in the background when you log in."
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        updateLoginSection()
    }

    @objc private func clearMemory() {
        store.clearMemory()
        updateHiddenItemsSection()
        memoryNote.stringValue = "Memory cleared"
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
            showHotkeyNote("Saved. " + Self.hotkeyHint)
        } else {
            showHotkeyNote("\(combo.displayString) is taken by the system or another app.", isError: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
    }
}
