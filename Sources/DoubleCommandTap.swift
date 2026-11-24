import AppKit
import ApplicationServices

final class DoubleCommandTap {
    static let maxGap: TimeInterval = 0.4
    private static let askedKey = "askedForAccessibility"

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private let onTrigger: () -> Void
    private var monitor: Any?
    private var commandIsDown = false
    private var otherInputSincePress = false
    private var lastCleanTap: Date?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    var hasPermission: Bool { AXIsProcessTrusted() }

    func start(promptForPermission: Bool) {
        let defaults = UserDefaults.standard
        if promptForPermission && !hasPermission && !defaults.bool(forKey: Self.askedKey) {
            defaults.set(true, forKey: Self.askedKey)
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
    }

    func handle(_ event: NSEvent) {
        handle(isKeyDown: event.type == .keyDown, modifiers: event.modifierFlags, at: Date())
    }

    func handle(isKeyDown: Bool, modifiers rawModifiers: NSEvent.ModifierFlags, at now: Date) {
        if isKeyDown {
            otherInputSincePress = true
            return
        }
        let modifiers = rawModifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if modifiers == .command {
            commandIsDown = true
            otherInputSincePress = false
        } else if modifiers.isEmpty && commandIsDown {
            commandIsDown = false
            registerRelease(clean: !otherInputSincePress, at: now)
        } else {
            otherInputSincePress = true
        }
    }

    private func registerRelease(clean: Bool, at now: Date) {
        guard clean else {
            lastCleanTap = nil
            return
        }
        if let last = lastCleanTap, now.timeIntervalSince(last) < Self.maxGap {
            lastCleanTap = nil
            onTrigger()
        } else {
            lastCleanTap = now
        }
    }
}
