import AppKit

/// Spotlight-style floating search over menu bar items.
///
/// Non-activating, so the app the user was in stays frontmost and the item's
/// menu opens over it. Closes on Esc, on choosing, or on losing key.
@MainActor
final class SearchPanel: NSPanel, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the chosen item after the panel has closed.
    /// The flag is true for ⌥Return / ⌥click, which asks for the right-click menu.
    var onChoose: ((MenuBarItem, _ alternate: Bool) -> Void)?
    /// ⌘, while the panel is open.
    var onOpenSettings: (() -> Void)?

    private static let width: CGFloat = 680
    private static let fieldHeight: CGFloat = 56
    private static let rowHeight: CGFloat = 44
    private static let maxVisibleRows = 8
    /// Separator, gap above the list and margin below it.
    private static let listChrome: CGFloat = 1 + 4 + 10

    private let field = NSTextField()
    private let table = NSTableView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let emptyLabel = NSTextField(labelWithString: "No menu bar items match")

    private var allItems: [MenuBarItem] = []
    private var results: [MenuBarItem] = []
    private var iconCache: [pid_t: NSImage] = [:]
    /// Anchors the panel's top edge while its height follows the result count.
    private var topY: CGFloat = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        delegate = self
        buildContent()
    }

    override var canBecomeKey: Bool { true }

    // MARK: Showing

    var isShowing: Bool { isVisible }

    func show(items: [MenuBarItem]) {
        field.stringValue = ""
        allItems = items
        refilter()

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            topY = frame.maxY - frame.height * 0.18
            setFrameOrigin(NSPoint(x: frame.midX - Self.width / 2, y: topY - self.frame.height))
        }
        resizeToFit()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    /// New scan results while open: keep the query, refresh the list.
    func update(items: [MenuBarItem]) {
        guard isVisible else { return }
        let selected = results.indices.contains(table.selectedRow) ? results[table.selectedRow].title : nil
        allItems = items
        refilter(keepSelection: selected)
    }

    func dismiss() {
        orderOut(nil)
    }

    /// While Barlight presses » itself, the panel loses key focus to the
    /// menu bar; that must not close it.
    private var isRevealing = false

    func setRevealing(_ revealing: Bool) {
        isRevealing = revealing
        if !revealing, isVisible, !isKeyWindow {
            makeKey()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isRevealing else { return }
        dismiss()
    }

    // MARK: Filtering and choosing

    private func refilter(keepSelection title: String? = nil) {
        results = Matcher.filter(allItems, query: field.stringValue)
        table.reloadData()
        let row = title.flatMap { t in results.firstIndex { $0.title == t } } ?? 0
        if !results.isEmpty {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        resizeToFit()
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), results.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func choose(row: Int, alternate: Bool = false) {
        guard results.indices.contains(row) else { return }
        let item = results[row]
        dismiss()
        onChoose?(item, alternate)
    }

    @objc private func rowClicked() {
        choose(row: table.clickedRow, alternate: NSEvent.modifierFlags.contains(.option))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "," {
            dismiss()
            onOpenSettings?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func controlTextDidChange(_ obj: Notification) {
        refilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(moveUp(_:)): moveSelection(by: -1)
        case #selector(moveDown(_:)): moveSelection(by: 1)
        case #selector(insertNewline(_:)): choose(row: table.selectedRow)
        // ⌥Return reaches the field editor as insertNewlineIgnoringFieldEditor.
        case #selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)): choose(row: table.selectedRow, alternate: true)
        case #selector(cancelOperation(_:)): dismiss()
        default: return false
        }
        return true
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCell.identifier, owner: nil) as? ResultCell ?? ResultCell()
        let item = results[row]
        cell.titleField.stringValue = item.title
        cell.subtitleField.stringValue = item.isHidden ? "\(item.appName) · hidden behind »" : item.appName
        cell.iconView.image = icon(for: item)
        return cell
    }

    private func icon(for item: MenuBarItem) -> NSImage? {
        if let cached = iconCache[item.pid] { return cached }
        let image: NSImage? = if item.bundleID == ItemScanner.menuBarAgentBundleID {
            NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/ControlCenter.app")
        } else {
            NSRunningApplication(processIdentifier: item.pid)?.icon
        }
        iconCache[item.pid] = image
        return image
    }

    // MARK: Layout

    private func resizeToFit() {
        // Without Accessibility the scan is empty; say why instead of showing nothing.
        let showsMessage = results.isEmpty && (!field.stringValue.isEmpty || !AXIsProcessTrusted())
        emptyLabel.stringValue = AXIsProcessTrusted()
            ? "No menu bar items match"
            : "Allow Barlight in System Settings › Privacy & Security › Accessibility"
        let listHeight: CGFloat
        if results.isEmpty {
            listHeight = showsMessage ? Self.rowHeight : 0
        } else {
            // Measure the table rather than multiplying row heights: the inset
            // style adds its own padding above the first and below the last row.
            let rows = min(results.count, Self.maxVisibleRows)
            // When the list scrolls, stop right at the last whole row: the
            // inset style's bottom padding would show a sliver of the next.
            let bottomPadding = results.count > rows ? 0 : table.rect(ofRow: 0).minY
            let tableHeight = table.rect(ofRow: rows - 1).maxY + bottomPadding
            listHeight = Self.listChrome + tableHeight
        }
        scrollView.isHidden = results.isEmpty
        emptyLabel.isHidden = !showsMessage
        separator.isHidden = listHeight == 0

        let height = Self.fieldHeight + listHeight
        setFrame(NSRect(x: frame.minX, y: topY - height, width: Self.width, height: height), display: true)
        // A borderless window's shadow follows its drawn shape, but only when
        // told to; otherwise the old rectangle shows at the rounded corners.
        invalidateShadow()
        DispatchQueue.main.async { [weak self] in self?.invalidateShadow() }
    }

    private func buildContent() {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 26
        // Clip to the rounded shape so nothing square pokes out at the corners.
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 26
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        let container = NSView()
        glass.contentView = container
        contentView = glass

        let glyph = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        glyph.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        glyph.contentTintColor = .secondaryLabelColor

        field.placeholderString = "Search menu bar items"
        field.font = .systemFont(ofSize: 22)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        separator.boxType = .separator

        let column = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.style = .inset
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.refusesFirstResponder = true

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14)

        for view in [glyph, field, separator, scrollView, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            glyph.centerYAnchor.constraint(equalTo: container.topAnchor, constant: Self.fieldHeight / 2),
            field.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: glyph.centerYAnchor),

            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.fieldHeight),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
        ])
    }
}

/// Draws the selected row in the accent colour even though the search field,
/// not the table, has keyboard focus.
private final class EmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

private final class ResultCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")

    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let subtitleField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        imageView = iconView
        textField = titleField

        titleField.font = .systemFont(ofSize: 15)
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.font = .systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleField, subtitleField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 0

        for view in [iconView, labels] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
