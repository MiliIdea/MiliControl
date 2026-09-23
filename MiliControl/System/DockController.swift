//
//  DockController.swift
//  MiliControl
//
//  Turns the Dock's "Automatically hide and show" on or off, live.
//
//  macOS has only one, system-wide auto-hide switch — there is no per-desktop
//  Dock setting — so MiliControl flips this switch as you change desktops.
//
//  Primary method: CoreDock's private CoreDockSetAutoHideEnabled /
//  CoreDockGetAutoHideEnabled, looked up at runtime with dlsym. Instant, no
//  Dock restart, no permission. They act on the LIVE Dock state; the Dock's
//  saved preference can lag behind, so we never use the preference to decide
//  what the Dock is currently doing when CoreDock is available.
//
//  If a future macOS removes CoreDock, we fall back to asking System Events
//  via AppleScript (one-time Automation prompt). Never crashes if neither is
//  available — it just reports `isAvailable == false`.
//

import Foundation
import os

final class DockController {

    private typealias SetAutoHide = @convention(c) (UInt8) -> Void
    private typealias GetAutoHide = @convention(c) () -> UInt8

    private let setAutoHideFn: SetAutoHide?
    private let getAutoHideFn: GetAutoHide?
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "dock")
    private var appleScriptFailed = false

    init() {
        let candidates = [
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        ]
        var setter: SetAutoHide?
        var getter: GetAutoHide?
        for path in candidates where setter == nil || getter == nil {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if setter == nil, let symbol = dlsym(handle, "CoreDockSetAutoHideEnabled") {
                setter = unsafeBitCast(symbol, to: SetAutoHide.self)
            }
            if getter == nil, let symbol = dlsym(handle, "CoreDockGetAutoHideEnabled") {
                getter = unsafeBitCast(symbol, to: GetAutoHide.self)
            }
        }
        setAutoHideFn = setter
        getAutoHideFn = getter
        if setter == nil { log.info("CoreDock not available; using AppleScript fallback") }
    }

    /// Whether MiliControl can change the Dock on this Mac.
    var isAvailable: Bool { setAutoHideFn != nil || !appleScriptFailed }

    /// The Dock's current (live) auto-hide state.
    var isAutoHideEnabled: Bool {
        if let get = getAutoHideFn { return get() != 0 }
        // Fallback: the saved preference (may lag behind the live Dock).
        return (SystemPreferences.value("autohide", in: "com.apple.dock") as? NSNumber)?.boolValue ?? false
    }

    /// Sets auto-hide. Always applied — never skipped based on a possibly
    /// stale reading — so the Dock reliably ends up in the requested state.
    func setAutoHide(_ hide: Bool) {
        if let setAutoHide = setAutoHideFn {
            // Skip only when the live state already matches.
            if let get = getAutoHideFn, (get() != 0) == hide { return }
            setAutoHide(hide ? 1 : 0)
            return
        }
        guard !appleScriptFailed else { return }
        let source = "tell application \"System Events\" to set autohide of dock preferences to \(hide)"
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            appleScriptFailed = true
            log.error("Dock AppleScript failed: \(String(describing: error), privacy: .public)")
        }
    }
}
