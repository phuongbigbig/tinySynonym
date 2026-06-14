import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var synonymPanel: SynonymPanel!
    private var selectionMonitor: SelectionMonitor!
    private var synonymProvider: SynonymProvider!

    private var maxSynonyms: Int {
        get { UserDefaults.standard.integer(forKey: "maxSynonyms").clamped(to: 1...20) }
        set { UserDefaults.standard.set(newValue, forKey: "maxSynonyms") }
    }

    private var isEnabled: Bool {
        get {
            // Default to true on first launch
            if UserDefaults.standard.object(forKey: "isEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "isEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "isEnabled") }
    }

    private var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Silently fail — user can toggle again
                }
            }
        }
    }

    private var currentWord: String = ""
    private var currentSynonyms: [TaggedSynonym] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set defaults on first launch
        if UserDefaults.standard.integer(forKey: "maxSynonyms") == 0 {
            UserDefaults.standard.set(8, forKey: "maxSynonyms")
        }

        setupStatusItem()
        synonymProvider = SynonymProvider()
        synonymPanel = SynonymPanel()

        if !checkAccessibility() {
            showAccessibilityAlert()
        }

        selectionMonitor = SelectionMonitor { [weak self] selectedText in
            DispatchQueue.main.async {
                self?.handleSelection(selectedText)
            }
        }

        if isEnabled {
            selectionMonitor.start()
        } else {
            statusItem.button?.alphaValue = 0.4
        }

        rebuildMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let img = NSImage(systemSymbolName: "text.book.closed.fill", accessibilityDescription: "Thesaurus") {
                let configured = img.withSymbolConfiguration(config) ?? img
                button.image = configured
            } else {
                button.title = "Th"
            }
            button.toolTip = "Menubar Thesaurus"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header
        let header = NSMenuItem(title: "MENUBAR THESAURUS", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "MENUBAR THESAURUS",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        // Synonym section
        if !currentSynonyms.isEmpty {
            let wordItem = NSMenuItem(title: "\"\(currentWord)\"", action: nil, keyEquivalent: "")
            wordItem.isEnabled = false
            wordItem.attributedTitle = NSAttributedString(
                string: "\"\(currentWord)\"",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            menu.addItem(wordItem)
            menu.addItem(NSMenuItem.separator())

            for tagged in currentSynonyms.prefix(maxSynonyms) {
                let item = NSMenuItem(title: tagged.word, action: #selector(copySynonym(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = tagged.word

                // Color-coded by source
                let sourceColor = SourceColors.color(for: tagged.source)
                item.attributedTitle = NSAttributedString(
                    string: "  \(tagged.word)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: sourceColor
                    ]
                )
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            let hint = NSMenuItem(title: "Click to copy", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            hint.attributedTitle = NSAttributedString(
                string: "Click to copy to clipboard",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
            menu.addItem(hint)
        } else {
            let noWord = NSMenuItem(title: "Select a word to see synonyms", action: nil, keyEquivalent: "")
            noWord.isEnabled = false
            menu.addItem(noWord)
        }

        menu.addItem(NSMenuItem.separator())

        // ── Settings ──

        // Enable/Disable toggle
        let toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)

        // Launch at Login toggle
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        // Offline-only toggle
        let offlineItem = NSMenuItem(title: "Offline Only", action: #selector(toggleOfflineOnly), keyEquivalent: "o")
        offlineItem.target = self
        offlineItem.state = synonymProvider.offlineOnly ? .on : .off
        menu.addItem(offlineItem)

        menu.addItem(NSMenuItem.separator())

        // Max synonyms submenu
        let maxItem = NSMenuItem(title: "Max Synonyms: \(maxSynonyms)", action: nil, keyEquivalent: "")
        let maxSubmenu = NSMenu()
        for n in [3, 5, 8, 10, 15] {
            let item = NSMenuItem(title: "\(n)", action: #selector(setMaxSynonyms(_:)), keyEquivalent: "")
            item.target = self
            item.tag = n
            if n == maxSynonyms { item.state = .on }
            maxSubmenu.addItem(item)
        }
        maxItem.submenu = maxSubmenu
        menu.addItem(maxItem)

        // Transparency submenu
        let currentOpacity = synonymPanel.panelOpacity
        let opacityPercent = Int(currentOpacity * 100)
        let opacityItem = NSMenuItem(title: "Dropdown Opacity: \(opacityPercent)%", action: nil, keyEquivalent: "")
        let opacitySubmenu = NSMenu()
        for pct in [30, 50, 65, 75, 85, 100] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if pct == opacityPercent { item.state = .on }
            opacitySubmenu.addItem(item)
        }
        opacityItem.submenu = opacitySubmenu
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())

        // Source color legend (text-only, no dots)
        let legendItem = NSMenuItem(title: "Source Colors", action: nil, keyEquivalent: "")
        let legendSubmenu = NSMenu()

        for (label, source) in [("Offline (curated)", SynonymSource.offline),
                                 ("Free Dictionary", SynonymSource.dictionary),
                                 ("Datamuse (synonym)", SynonymSource.datamuse),
                                 ("Datamuse (means like)", SynonymSource.meansLike)] {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: label,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: SourceColors.color(for: source)
                ]
            )
            legendSubmenu.addItem(item)
        }

        legendItem.submenu = legendSubmenu
        menu.addItem(legendItem)

        menu.addItem(NSMenuItem.separator())

        // Diagnostics submenu
        let diagItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let diagSubmenu = NSMenu()

        let axStatus = selectionMonitor.hasAccessibility ? "✅ Granted" : "❌ Not Granted"
        let axItem = NSMenuItem(title: "Accessibility: \(axStatus)", action: nil, keyEquivalent: "")
        axItem.isEnabled = false
        diagSubmenu.addItem(axItem)

        let monStatus = selectionMonitor.isRunning ? "✅ Active" : "⏸ Stopped"
        let monItem = NSMenuItem(title: "Monitoring: \(monStatus)", action: nil, keyEquivalent: "")
        monItem.isEnabled = false
        diagSubmenu.addItem(monItem)

        let srcMode = synonymProvider.offlineOnly ? "Offline Only" : "Online + Offline"
        let srcItem = NSMenuItem(title: "Source: \(srcMode)", action: nil, keyEquivalent: "")
        srcItem.isEnabled = false
        diagSubmenu.addItem(srcItem)

        if let err = selectionMonitor.lastError {
            let errItem = NSMenuItem(title: "⚠ \(err)", action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            diagSubmenu.addItem(errItem)
        }

        if !selectionMonitor.hasAccessibility {
            diagSubmenu.addItem(NSMenuItem.separator())
            let fixItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fixItem.target = self
            diagSubmenu.addItem(fixItem)
        }

        diagItem.submenu = diagSubmenu
        menu.addItem(diagItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Selection Handling

    private func handleSelection(_ text: String?) {
        guard isEnabled else { return }

        guard let text = text,
              !text.isEmpty,
              text.count > 1,
              text.count < 30,
              !text.contains(" "),
              text.allSatisfy({ $0.isLetter }) else {
            if !currentWord.isEmpty {
                currentWord = ""
                currentSynonyms = []
                rebuildMenu()
                synonymPanel.hide()
            }
            return
        }

        let word = text.lowercased()
        guard word != currentWord else { return }
        currentWord = word

        synonymProvider.getSynonyms(for: word, maxResults: maxSynonyms) { [weak self] synonyms in
            // Completion is guaranteed to be on the main thread
            guard let self = self, self.currentWord == word else { return }

            if synonyms.isEmpty {
                self.currentSynonyms = []
                self.rebuildMenu()
                self.synonymPanel.hide()
            } else {
                self.currentSynonyms = Array(synonyms.prefix(self.maxSynonyms))
                self.rebuildMenu()
                self.showSynonymDropdown(word: word, synonyms: self.currentSynonyms)
            }
        }
    }

    private func showSynonymDropdown(word: String, synonyms: [TaggedSynonym]) {
        guard let button = statusItem.button,
              let window = button.window else { return }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        synonymPanel.show(
            word: word,
            synonyms: synonyms,
            anchorRect: buttonRect
        ) { [weak self] synonym in
            self?.copyToClipboard(synonym)
        }
    }

    // MARK: - Actions

    @objc private func copySynonym(_ sender: NSMenuItem) {
        if let synonym = sender.representedObject as? String {
            copyToClipboard(synonym)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if let button = statusItem.button {
            let original = button.image
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")?
                .withSymbolConfiguration(config)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                button.image = original
            }
        }
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            selectionMonitor.start()
            statusItem.button?.alphaValue = 1.0
        } else {
            selectionMonitor.stop()
            currentWord = ""
            currentSynonyms = []
            synonymPanel.hide()
            statusItem.button?.alphaValue = 0.4
        }
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
        rebuildMenu()
    }

    @objc private func toggleOfflineOnly() {
        synonymProvider.offlineOnly.toggle()
        synonymProvider.clearCache()
        // Re-lookup current word if any
        if !currentWord.isEmpty {
            let word = currentWord
            currentWord = ""
            handleSelection(word)
        }
        rebuildMenu()
    }

    @objc private func setMaxSynonyms(_ sender: NSMenuItem) {
        maxSynonyms = sender.tag
        if !currentWord.isEmpty {
            let word = currentWord
            currentWord = ""
            handleSelection(word)
        }
        rebuildMenu()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        let opacity = CGFloat(sender.tag) / 100.0
        synonymPanel.panelOpacity = opacity
        synonymPanel.updateOpacity()
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Menubar Thesaurus needs Accessibility access to read selected text.\n\nPlease grant access in System Settings > Privacy & Security > Accessibility, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
