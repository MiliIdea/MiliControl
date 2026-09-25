//
//  DesktopSnapshots.swift
//  MiliControl
//
//  Remembers what each desktop looked like the last time you were on it,
//  for the previews in the navigation grid and the grid editor.
//
//  When it captures (only while "Show desktop previews" is on and Screen
//  Recording is granted):
//    • shortly after you arrive on a desktop (once the slide has settled),
//    • every few seconds while you stay there, so it stays fresh,
//    • right before the grid or the editor opens.
//
//  Guards against wrong previews:
//    • a capture is thrown away if the desktop changed while it was taken;
//    • no captures while a switch is under way (MiliControl knows before
//      macOS reports the change) or while the screen is locked;
//    • the image is taken from the display that desktop lives on.
//
//  Snapshots live in memory only — never written to disk — and are cleared
//  when previews are turned off.
//

import AppKit
import Combine
import os

final class DesktopSnapshots: ObservableObject {

    /// Latest snapshot per desktop key.
    @Published private(set) var images: [String: NSImage] = [:]
    /// Cached Screen Recording state (checked on enable and on each capture).
    @Published private(set) var permissionGranted = ScreenCapture.hasPermission

    private let desktops: DesktopStore
    private let prefs: Preferences
    /// True while a MiliControl overlay (HUD / editor) is on screen.
    private let overlaysVisible: () -> Bool
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "previews")

    private var spaceGeneration = 0              // bumped whenever the desktop changes
    private var quietUntil = Date.distantPast    // no captures during a switch
    private var isCapturing = false
    private var wantsRecapture = false
    private var refreshTimer: Timer?
    private var arrivalWork: DispatchWorkItem?
    private var spaceObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    private static let captureWidth = 480                  // px — plenty for thumbnails
    private static let arrivalDelay: TimeInterval = 0.5
    private static let refreshInterval: TimeInterval = 10

    init(desktops: DesktopStore, prefs: Preferences, overlaysVisible: @escaping () -> Bool) {
        self.desktops = desktops
        self.prefs = prefs
        self.overlaysVisible = overlaysVisible
    }

    deinit {
        if let o = spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        refreshTimer?.invalidate()
    }

    /// Previews are on and allowed.
    var isActive: Bool { prefs.showPreviews && permissionGranted }

    func start() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.spaceDidChange()
            }

        prefs.$showPreviews
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)

        // Forget previews of desktops and fullscreen apps that no longer exist.
        desktops.$desktops.map { _ in () }
            .merge(with: desktops.$fullscreens.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // `@Published` fires before storing; read the store next pass.
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let live = Set(self.desktops.desktops.map(\.key) + self.desktops.fullscreens.map(\.key))
                    let kept = self.images.filter { live.contains($0.key) }
                    if kept.count != self.images.count { self.images = kept }
                }
            }
            .store(in: &cancellables)
    }

    /// Captures the current desktop now (e.g. right before the grid opens).
    func captureNow() {
        capture()
    }

    /// Called by MiliControl as it switches desktops, so nothing is captured
    /// mid-slide and attributed to the wrong desktop. `duration` covers every
    /// slide of a multi-step route.
    func switchWillStart(duration: TimeInterval) {
        spaceGeneration += 1
        arrivalWork?.cancel()
        quietUntil = Date().addingTimeInterval(duration)
    }

    // MARK: - Lifecycle

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            permissionGranted = ScreenCapture.hasPermission
            if !permissionGranted { ScreenCapture.requestPermission() }
            startRefreshTimer()
            capture()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            arrivalWork?.cancel()
            images.removeAll()
        }
    }

    private func spaceDidChange() {
        spaceGeneration += 1                        // invalidates in-flight captures
        arrivalWork?.cancel()
        guard prefs.showPreviews else { return }
        // Wait for the slide to settle — and, during a multi-slide route, for
        // the whole route to finish (each intermediate change reschedules this).
        let delay = max(Self.arrivalDelay, quietUntil.timeIntervalSinceNow + 0.1)
        let work = DispatchWorkItem { [weak self] in self?.capture() }
        arrivalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.capture()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Capture

    private func capture() {
        guard prefs.showPreviews else { return }
        if !permissionGranted {
            permissionGranted = ScreenCapture.hasPermission
            guard permissionGranted else { return }
        }
        if isCapturing {                             // run once more when this one ends
            wantsRecapture = true
            return
        }
        guard Date() >= quietUntil, !overlaysVisible(), !Self.isScreenLocked,
              let key = desktops.currentKey,                    // a desktop or fullscreen app
              let desktop = desktops.space(forKey: key) else { return }

        isCapturing = true
        let generation = spaceGeneration
        let display = ScreenCapture.displayID(forIdentifier: desktop.displayID)

        ScreenCapture.capture(display: display, width: Self.captureWidth) { [weak self] image in
            guard let self = self else { return }
            self.isCapturing = false
            defer {
                if self.wantsRecapture {
                    self.wantsRecapture = false
                    self.capture()
                }
            }
            // Discard if you switched desktops while this was being taken.
            guard let image = image,
                  generation == self.spaceGeneration,
                  Date() >= self.quietUntil,
                  self.desktops.currentKey == key,
                  self.prefs.showPreviews else { return }
            self.images[key] = NSImage(cgImage: image, size: .zero)
        }
    }

    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }
}
