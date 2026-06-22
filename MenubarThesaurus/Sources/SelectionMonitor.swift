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
    /// Uses multiple strategies to handle apps like Microsoft Word that have
    /// non-standard accessibility implementations.
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

        let app = focusedAppRef as! AXUIElement

        // Get the focused UI element within the app
        var focusedElemRef: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElemRef
        )
        guard elemResult == .success else {
            lastError = nil
            return nil
        }

        let element = focusedElemRef as! AXUIElement

        // Strategy 1: Direct kAXSelectedTextAttribute on focused element (works for most apps)
        if let text = getAXSelectedText(from: element) {
            return text
        }

        // Strategy 2: Try kAXSelectedTextRangeAttribute + kAXStringForRangeParameterizedAttribute
        // This works for apps like Word that expose range-based text access
        if let text = getSelectedTextViaRange(from: element) {
            return text
        }

        // Strategy 3: Walk up the element hierarchy — some apps (Word, Outlook) expose
        // selected text on a parent element rather than the deepest focused element
        var current = element
        for _ in 0..<4 {
            var parentRef: AnyObject?
            let parentResult = AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parentRef
            )
            guard parentResult == .success else { break }
            let parent = parentRef as! AXUIElement

            if let text = getAXSelectedText(from: parent) {
                return text
            }
            if let text = getSelectedTextViaRange(from: parent) {
                return text
            }
            current = parent
        }

        // Strategy 4: Try getting selected text directly from the app element
        if let text = getAXSelectedText(from: app) {
            return text
        }

        lastError = nil
        return nil
    }

    /// Get kAXSelectedTextAttribute from an element.
    private func getAXSelectedText(from element: AXUIElement) -> String? {
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &ref
        )
        guard result == .success, let text = ref as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Get selected text via range parameterized attribute.
    /// Some apps (Word, Pages) support this even when kAXSelectedTextAttribute fails.
    private func getSelectedTextViaRange(from element: AXUIElement) -> String? {
        // First get the selected text range
        var rangeRef: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeResult == .success, let rangeValue = rangeRef else { return nil }

        // Extract the CFRange
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        guard range.length > 0, range.length <= 30 else { return nil }

        // Use the parameterized attribute to get the string for that range
        var textRef: AnyObject?
        let textResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textRef
        )
        guard textResult == .success, let text = textRef as? String else { return nil }
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
