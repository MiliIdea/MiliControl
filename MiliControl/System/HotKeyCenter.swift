//
//  HotKeyCenter.swift
//  MiliControl
//
//  System-wide hotkeys via Carbon's RegisterEventHotKey — still the most
//  reliable way on macOS to own a global shortcut without an event tap.
//  Supports any number of hotkeys through one shared event handler.
//

import Carbon.HIToolbox
import os

struct HotKeySpec: Equatable {
    let keyCode: UInt32
    /// Carbon modifier mask (controlKey, optionKey, cmdKey, shiftKey).
    let modifiers: UInt32
    let name: String

    static let arrowLeft: UInt32 = 123
    static let arrowRight: UInt32 = 124
    static let arrowDown: UInt32 = 125
    static let arrowUp: UInt32 = 126
    static let space: UInt32 = 49

    static let controlOption = UInt32(controlKey | optionKey)
    static let control = UInt32(controlKey)
}

final class HotKeyCenter {

    private static let signature: OSType = 0x4D49_4C49          // 'MILI'

    private struct Handlers {
        let press: () -> Void
        let release: (() -> Void)?
    }

    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: Handlers] = [:]
    private var nextID: UInt32 = 1
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "hotkeys")

    /// Names of hotkeys that could not be registered (usually because another
    /// app already owns that combination).
    private(set) var failures: [String] = []

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers a hotkey. `action` runs when the key goes down, `onRelease`
    /// (optional) when that key comes back up. Returns false (and records a
    /// failure) if macOS refused — typically because the combo is taken.
    @discardableResult
    func register(_ spec: HotKeySpec,
                  onRelease: (() -> Void)? = nil,
                  action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref = ref else {
            log.error("Could not register \(spec.name, privacy: .public): \(status)")
            failures.append(spec.name)
            return false
        }
        refs[id] = ref
        actions[id] = Handlers(press: action, release: onRelease)
        return true
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        failures.removeAll()
    }

    fileprivate func fire(_ id: UInt32, released: Bool) {
        guard let handlers = actions[id] else { return }
        if released { handlers.release?() } else { handlers.press() }
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            center.fire(hotKeyID.id, released: released)
            return noErr
        }, 2, &eventTypes, context, &handlerRef)   // 2 = pressed + released
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
    }
}
