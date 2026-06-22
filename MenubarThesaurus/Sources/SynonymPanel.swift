import Cocoa

/// Colors for each synonym source.
struct SourceColors {
    /// Offline / curated thesaurus — default label color (white in dark, black in light)
    static let offline = NSColor.labelColor

    /// Free Dictionary API — soft teal/cyan
    static let dictionary = NSColor(calibratedRed: 0.30, green: 0.75, blue: 0.72, alpha: 1.0)

    /// Datamuse API — soft lavender/purple
    static let datamuse = NSColor(calibratedRed: 0.65, green: 0.55, blue: 0.90, alpha: 1.0)

    /// Datamuse "means like" — soft warm amber/orange
    static let meansLike = NSColor(calibratedRed: 0.85, green: 0.65, blue: 0.35, alpha: 1.0)

    static func color(for source: SynonymSource) -> NSColor {
        switch source {
        case .offline:    return offline
        case .dictionary: return dictionary
        case .datamuse:   return datamuse
        case .meansLike:  return meansLike
        }
    }

}

/// A small floating panel that appears below the menu bar icon showing synonyms.
class SynonymPanel {

    private var panel: NSPanel?
    private var onSelect: ((String) -> Void)?
    private var dismissTimer: Timer?

    /// Panel opacity (0.3 to 1.0). Stored in UserDefaults.
    var panelOpacity: CGFloat {
        get {
            let stored = CGFloat(UserDefaults.standard.float(forKey: "panelOpacity"))
            return stored > 0.1 ? stored : 0.85 // default
        }
        set {
            UserDefaults.standard.set(Float(newValue), forKey: "panelOpacity")
        }
    }

    func show(word: String, synonyms: [TaggedSynonym], anchorRect: NSRect, nearCursor: Bool = false, onSelect: @escaping (String) -> Void) {
        hide()
        self.onSelect = onSelect

        let width: CGFloat = 200
        let rowHeight: CGFloat = 26
        let headerHeight: CGFloat = 28
        let footerHeight: CGFloat = 20
        let padding: CGFloat = 6

        let totalHeight = headerHeight + CGFloat(synonyms.count) * rowHeight
            + footerHeight + padding * 2

        let x: CGFloat
        let y: CGFloat

        if nearCursor {
            // Position above-right of cursor, keeping on screen
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let candidateX = anchorRect.midX + 12
            let candidateY = anchorRect.midY - 10

            // Keep panel on screen horizontally
            x = min(candidateX, screenFrame.maxX - width - 8)
            // Keep panel on screen vertically; prefer showing below cursor if near top
            if candidateY + totalHeight > screenFrame.maxY {
                y = candidateY - totalHeight
            } else {
                y = candidateY
            }
        } else {
            // Position below menu bar icon
            x = anchorRect.midX - width / 2
            y = anchorRect.minY - totalHeight - 4
        }

        let frame = NSRect(x: x, y: y, width: width, height: totalHeight)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.alphaValue = panelOpacity

        // Container view with vibrancy
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.material = .popover
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.blendingMode = .behindWindow

        var yOffset = totalHeight - padding

        // Header: word
        yOffset -= headerHeight
        let headerLabel = NSTextField(labelWithString: word)
        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.frame = NSRect(x: 12, y: yOffset, width: width - 24, height: headerHeight)
        container.addSubview(headerLabel)

        // Synonym rows
        for tagged in synonyms {
            yOffset -= rowHeight
            let rowView = SynonymRowView(
                frame: NSRect(x: 4, y: yOffset, width: width - 8, height: rowHeight),
                synonym: tagged.word,
                source: tagged.source
            ) { [weak self] selected in
                self?.onSelect?(selected)
                self?.hide()
            }
            container.addSubview(rowView)
        }

        // Footer hint
        yOffset -= footerHeight
        let hintLabel = NSTextField(labelWithString: "click to copy")
        hintLabel.font = NSFont.systemFont(ofSize: 9)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.frame = NSRect(x: 12, y: yOffset, width: width - 24, height: footerHeight)
        container.addSubview(hintLabel)

        p.contentView = container
        p.orderFrontRegardless()

        self.panel = p

        // Auto-dismiss after 10 seconds
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
        onSelect = nil
    }

    /// Update opacity on an already-visible panel
    func updateOpacity() {
        panel?.alphaValue = panelOpacity
    }

}

// MARK: - Synonym Row View

private class SynonymRowView: NSView {

    private let synonym: String
    private let source: SynonymSource
    private let onClick: (String) -> Void
    private var isHovered = false
    private let label: NSTextField

    init(frame: NSRect, synonym: String, source: SynonymSource, onClick: @escaping (String) -> Void) {
        self.synonym = synonym
        self.source = source
        self.onClick = onClick
        self.label = NSTextField(labelWithString: synonym)
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 4

        // Synonym text — color-coded by source (no dot)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = SourceColors.color(for: source)
        label.frame = NSRect(x: 10, y: 0, width: frame.width - 18, height: frame.height)
        addSubview(label)

        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        label.textColor = .controlAccentColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = nil
        label.textColor = SourceColors.color(for: source)
    }

    override func mouseUp(with event: NSEvent) {
        onClick(synonym)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
