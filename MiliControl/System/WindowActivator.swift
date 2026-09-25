//
//  WindowActivator.swift
//  MiliControl
//
//  Brings a fullscreen app's window forward — the same thing clicking it in
//  the Dock does. macOS then slides to that window's space with its own
//  animation (System Settings ▸ Desktop & Dock ▸ "When switching to an
//  application, switch to a Space with open windows" must be on; it is by
//  default, and the setup checklist watches it).
//
//  Uses Accessibility (MiliControl already has it): the exact window is
//  raised, then its app is made frontmost. Window IDs are matched to
//  Accessibility windows with `_AXUIElementGetWindow`, a long-standing
//  private call that window managers rely on. If the window can't be found
//  (e.g. the app doesn't list it), the app is still brought forward, and the
//  switcher falls back to stepping if that doesn't reach the space.
//

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowActivator {

    /// Raises the apps' fullscreen windows (the first one ends up in front)
    /// and activates it. Returns false if the app is gone or refuses.
    @discardableResult
    static func bringForward(_ apps: [FullscreenApp]) -> Bool {
        guard let primary = apps.first else { return false }
        // Split View: raise the partner first, so the primary ends up key.
        for app in apps.dropFirst() { raise(app) }
        raise(primary)
        return activate(primary.pid)
    }

    private static func raise(_ app: FullscreenApp) {
        let element = AXUIElementCreateApplication(app.pid)
        guard let windowID = app.windowID, let window = window(withID: windowID, in: element) else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    private static func activate(_ pid: pid_t) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
            return false
        }
        // Frontmost through Accessibility works even though MiliControl
        // itself is in the background (plain activation may be declined).
        let element = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if result == .success { return true }
        if #available(macOS 14.0, *) {
            return running.activate()
        }
        return running.activate(options: [.activateIgnoringOtherApps])
    }

    private static func window(withID id: CGWindowID, in app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { window in
            var windowID: CGWindowID = 0
            return _AXUIElementGetWindow(window, &windowID) == .success && windowID == id
        }
    }
}
