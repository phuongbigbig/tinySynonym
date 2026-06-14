import Cocoa
import ApplicationServices

/// Monitors text selection across all apps using the Accessibility API.
/// Polls the focused UI element's selected text at a regular interval.
class SelectionMonitor {

    private var timer: Timer?
    private let interval: TimeInterval = 0.4
    private let onSelectionChanged: (String?) -> Void
    private var lastSelection: String?

    /// Diagnostic: last error from AX API (for debug menu)
    private(set) var lastError: String?
    /// Diagnostic: whether monitoring is actively running
    private(set) var isRunning: Bool = false
    /// Diagnostic: whether accessibility is available
    private(set) var hasAccessibility: Bool = false

    init(onSelectionChanged: @escaping (String?) -> Void) {
        self.onSelectionChanged = onSelectionChanged
    }

    func start() {
        stop()
        isRunning = true
        lastError = nil

        // Check accessibility upfront
        hasAccessibility = AXIsProcessTrusted()

        // Always schedule on the main run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let timer = Timer(timeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.pollSelection()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer

            // Fire immediately
            self.pollSelection()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        lastSelection = nil
    }

    // MARK: - Polling

    private func pollSelection() {
        // Re-check accessibility on each poll (user might grant it mid-session)
        hasAccessibility = AXIsProcessTrusted()

        guard hasAccessibility else {
            lastError = "No accessibility permission"
            // Still notify nil so the panel can dismiss
            if lastSelection != nil {
                lastSelection = nil
                onSelectionChanged(nil)
            }
            return
        }

        let selectedText = getSelectedText()

        // Only notify on change
        guard selectedText != lastSelection else { return }
        lastSelection = selectedText

        // Filter: only single English words
        if let text = selectedText, isEnglishWord(text) {
            lastError = nil
            onSelectionChanged(text)
        } else {
            onSelectionChanged(nil)
        }
    }

    /// Reads the selected text from the currently focused UI element.
    private func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedAppRef: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appResult == .success else {
            lastError = "Cannot get focused app (AX error \(appResult.rawValue))"
            return nil
        }

        // AXUIElementCopyAttributeValue returns CFTypeRef; cast safely
        let app = focusedAppRef as! AXUIElement  // this specific attribute always returns AXUIElement

        // Get the focused UI element within the app
        var focusedElemRef: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElemRef
        )
        guard elemResult == .success else {
            // Not all apps expose focused element — this is normal
            lastError = nil
            return nil
        }

        let element = focusedElemRef as! AXUIElement

        // Get selected text from the focused element
        var selectedTextRef: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        guard textResult == .success else {
            // Element doesn't support selected text — normal for many UI elements
            lastError = nil
            return nil
        }

        guard let text = selectedTextRef as? String else {
            lastError = nil
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Check if text looks like a single English word.
    private func isEnglishWord(_ text: String) -> Bool {
        guard text.count >= 2, text.count <= 25 else { return false }
        guard !text.contains(" ") else { return false }
        // Allow letters and hyphens (for compound words like "well-known")
        return text.allSatisfy { $0.isLetter || $0 == "-" }
    }
}
