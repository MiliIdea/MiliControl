//
//  TrackpadSwipes.swift
//  MiliControl
//
//  Recognizes four-finger swipes on the trackpad (built-in or Magic
//  Trackpad), anywhere on the Mac, and reports one direction per swipe.
//
//  macOS doesn't deliver multi-finger gestures to other apps, so this reads
//  raw finger positions from Apple's private MultitouchSupport framework —
//  the same source tools like BetterTouchTool use. Everything is looked up at
//  runtime (dlopen/dlsym): if a future macOS changes or removes it,
//  `isAvailable` is false and nothing else in MiliControl is affected.
//
//  Direction follows the content, like macOS: fingers moving left reveal the
//  desktop on the right; fingers moving up reveal the row below.
//
//  The swipe is recognized while the fingers move, but the switch happens
//  when they lift — macOS drops desktop switches sent mid-gesture.
//

import Foundation
import CoreGraphics
import Combine
import os

final class TrackpadSwipes: ObservableObject {

    static let shared = TrackpadSwipes()

    /// Called on the main queue, once per recognized swipe.
    var onSwipe: ((NavDirection) -> Void)?

    // Live state for the Settings "trackpad test" (main queue only).
    /// Number of trackpads MiliControl is listening to.
    @Published private(set) var deviceCount = 0
    /// Whether any touch data has arrived since listening started.
    @Published private(set) var receivedTouches = false
    /// Fingers currently on the trackpad.
    @Published private(set) var fingerCount = 0
    /// The most recent swipe recognized.
    @Published private(set) var lastSwipe: NavDirection?

    /// Input Monitoring — recent macOS may withhold raw trackpad input without it.
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }
    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    // MultitouchSupport entry points (resolved at runtime).
    private typealias ContactCallback = @convention(c)
        (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer?, ContactCallback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private let createList: CreateList?
    private let register: Register?
    private let unregister: Register?
    private let start: Start?
    private let stop: Stop?

    private var devices: CFArray?
    private(set) var isRunning = false
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "gestures")

    // Recognizer state — touched only from the multitouch thread, under `lock`.
    private let lock = NSLock()
    /// The trackpad currently being followed (built-in and Magic Trackpad
    /// can both be attached; only one gesture is tracked at a time).
    private var activeDevice: UnsafeMutableRawPointer?
    private var tracking = false
    private var firedThisContact = false
    /// Recognized during the swipe; delivered when the fingers lift.
    private var pendingSwipe: NavDirection?
    private var startPoint = (x: Float(0), y: Float(0))
    /// Last finger count / "any touches" reported to the main queue (so the
    /// UI is updated only on change, not on every frame).
    private var reportedFingerCount = -1
    private var reportedTouches = false

    /// Fingers on the followed trackpad right now (for the scroll blocker).
    private var fingersDown = 0
    /// A trackpad scroll was swallowed because of a multi-finger touch; keep
    /// swallowing that scroll (including its momentum) until a new one starts.
    private var swallowingScroll = false

    /// Scroll blocker: an event tap that drops trackpad scrolling while 3+
    /// fingers are down, so a four-finger swipe doesn't nudge the page under
    /// the pointer. Runs on the main run loop.
    private var scrollTap: CFMachPort?
    private var scrollTapSource: CFRunLoopSource?

    /// Fraction of the trackpad the fingers must travel.
    private static let horizontalDistance: Float = 0.07
    private static let verticalDistance: Float = 0.08
    /// How much the main axis must dominate the other one.
    private static let dominance: Float = 1.3

    // Layout of one touch record (MTTouch): normalized x/y live at bytes 32/36.
    private static let touchStride = 96
    private static let normalizedXOffset = 32
    private static let normalizedYOffset = 36

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle = handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        createList = symbol("MTDeviceCreateList", as: CreateList.self)
        register = symbol("MTRegisterContactFrameCallback", as: Register.self)
        unregister = symbol("MTUnregisterContactFrameCallback", as: Register.self)
        start = symbol("MTDeviceStart", as: Start.self)
        stop = symbol("MTDeviceStop", as: Stop.self)
        if !isAvailable { log.info("MultitouchSupport unavailable; four-finger swipes disabled") }
    }

    /// Whether this Mac lets MiliControl read the trackpad.
    var isAvailable: Bool {
        createList != nil && register != nil && unregister != nil && start != nil && stop != nil
    }

    // MARK: - Start / stop

    func startListening() {
        guard isAvailable, !isRunning,
              let createList = createList, let register = register, let start = start,
              let list = createList()?.takeRetainedValue() else { return }
        devices = list
        for index in 0 ..< CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, trackpadContactCallback)
            start(device, 0)
        }
        isRunning = true
        installScrollBlocker()
        deviceCount = CFArrayGetCount(list)
        lock.lock(); reportedTouches = false; reportedFingerCount = -1; lock.unlock()
        receivedTouches = false
        log.debug("Listening on \(CFArrayGetCount(list), privacy: .public) multitouch device(s)")
    }

    func stopListening() {
        guard isRunning, let list = devices, let unregister = unregister, let stop = stop else { return }
        for index in 0 ..< CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            unregister(device, trackpadContactCallback)
            stop(device)
        }
        devices = nil
        isRunning = false
        removeScrollBlocker()
        deviceCount = 0
        fingerCount = 0
        lock.lock()
        tracking = false; firedThisContact = false; activeDevice = nil; pendingSwipe = nil
        fingersDown = 0; swallowingScroll = false
        lock.unlock()
    }

    // MARK: - Scroll blocker

    private func installScrollBlocker() {
        guard scrollTap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        // Needs Accessibility (MiliControl already has it to switch desktops).
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: scrollTapCallback, userInfo: nil) else {
            log.info("Scroll blocker unavailable (no Accessibility yet); swipes still work")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        scrollTap = tap
        scrollTapSource = source
    }

    private func removeScrollBlocker() {
        if let tap = scrollTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = scrollTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        scrollTap = nil
        scrollTapSource = nil
    }

    /// Returns the event to pass it on, or nil to drop it.
    fileprivate func filterScroll(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = scrollTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Only trackpad (continuous) scrolling; mouse wheels are left alone.
        guard type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else {
            return Unmanaged.passUnretained(event)
        }
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        lock.lock()
        defer { lock.unlock() }
        if fingersDown >= 3 {
            swallowingScroll = true
            return nil
        }
        if swallowingScroll {
            // A fresh two-finger scroll (phase "began", no momentum) ends the
            // swallowing; anything else is the tail of the swipe — drop it.
            if phase == 1 && momentum == 0 {
                swallowingScroll = false
                return Unmanaged.passUnretained(event)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Re-attaches to all devices (after wake, or a trackpad connecting).
    func restart() {
        guard isRunning else { return }
        stopListening()
        startListening()
    }

    // MARK: - Recognition (multitouch thread)

    fileprivate func process(device: UnsafeMutableRawPointer?, touches: UnsafeMutableRawPointer?, count: Int) {
        lock.lock()
        defer { lock.unlock() }

        // Feed the Settings "trackpad test" (only when something changes).
        if !reportedTouches || count != reportedFingerCount {
            reportedTouches = true
            reportedFingerCount = count
            DispatchQueue.main.async { [weak self] in
                self?.receivedTouches = true
                self?.fingerCount = count
            }
        }

        // Ignore a second trackpad while one is being followed.
        if let active = activeDevice, active != device { return }
        fingersDown = count

        guard count == 4, let touches = touches else {
            tracking = false
            // Fingers lifted (0 or 1 left, e.g. a resting thumb): the gesture is
            // over. Only NOW deliver the swipe — macOS ignores desktop switches
            // that arrive while a trackpad gesture is still in progress.
            if count <= 1, let swipe = pendingSwipe {
                pendingSwipe = nil
                DispatchQueue.main.async { [weak self] in self?.onSwipe?(swipe) }
            }
            if count == 0 {
                firedThisContact = false
                activeDevice = nil
            }
            return
        }
        activeDevice = device

        var sumX: Float = 0
        var sumY: Float = 0
        for index in 0 ..< count {
            let base = touches.advanced(by: index * Self.touchStride)
            sumX += base.load(fromByteOffset: Self.normalizedXOffset, as: Float.self)
            sumY += base.load(fromByteOffset: Self.normalizedYOffset, as: Float.self)
        }
        let center = (x: sumX / 4, y: sumY / 4)

        guard tracking else {
            tracking = true
            startPoint = center
            return
        }
        guard !firedThisContact else { return }                   // one step per swipe

        let dx = center.x - startPoint.x
        let dy = center.y - startPoint.y
        var direction: NavDirection?
        if abs(dx) > Self.horizontalDistance, abs(dx) > abs(dy) * Self.dominance {
            direction = dx < 0 ? .right : .left
        } else if abs(dy) > Self.verticalDistance, abs(dy) > abs(dx) * Self.dominance {
            direction = dy > 0 ? .down : .up
        }
        guard let swipe = direction else { return }
        firedThisContact = true
        pendingSwipe = swipe                                      // switched on lift
        DispatchQueue.main.async { [weak self] in self?.lastSwipe = swipe }
    }
}

/// C callback for MultitouchSupport: can't capture context, so it forwards to
/// the shared recognizer. Runs on the framework's own thread.
private let trackpadContactCallback: @convention(c)
    (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32 = {
        device, touches, count, _, _ in
        TrackpadSwipes.shared.process(device: device, touches: touches, count: Int(count))
        return 0
    }

/// C callback for the scroll-blocker event tap.
private let scrollTapCallback: CGEventTapCallBack = { _, type, event, _ in
    TrackpadSwipes.shared.filterScroll(type: type, event: event)
}
