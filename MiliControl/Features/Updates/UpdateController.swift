//
//  UpdateController.swift
//  MiliControl
//
//  Automatic updates with Sparkle.
//
//  Feed:  the `appcast.xml` attached to the latest GitHub release
//         (Info.plist ▸ SUFeedURL). Every release carries its own appcast,
//         so `releases/latest/download/appcast.xml` always points at the
//         newest version — no server, no GitHub Pages.
//  Trust: each update is EdDSA-signed with a key that lives only in the
//         developer's Keychain; the app checks it against SUPublicEDKey
//         (and macOS checks the Developer ID signature + notarization).
//
//  MiliControl is a menu-bar app that's almost never frontmost, so updates
//  found by the daily background check don't pop a window over your work.
//  They're announced "gently" instead: a badge on the menu-bar icon, a menu
//  item, and a banner in Settings. Checking by hand shows Sparkle's window
//  straight away.
//

import AppKit
import Combine
import Sparkle
import os

final class UpdateController: NSObject, ObservableObject {

    /// False when this build has no feed URL or public key (e.g. a local
    /// build before `Scripts/setup_updates.sh` has run). Updates stay off.
    private(set) var isConfigured: Bool

    /// Whether a check can start now (false while one is running).
    @Published private(set) var canCheckForUpdates = false
    /// When the last check finished.
    @Published private(set) var lastCheck: Date?
    /// A newer version found in the background, waiting for the user.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "updates")

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty
        super.init()

        if isConfigured {
            let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                          updaterDelegate: self,
                                                          userDriverDelegate: self)
            do {
                try controller.updater.start()
                self.controller = controller
            } catch {
                log.error("Updater didn't start: \(error.localizedDescription, privacy: .public)")
                isConfigured = false
            }
        } else {
            log.info("Updates not configured in this build (no SUFeedURL / SUPublicEDKey)")
        }

        guard let updater = controller?.updater else { return }
        lastCheck = updater.lastUpdateCheckDate
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    /// Daily background check. Sparkle remembers the choice.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Download in the background and install when MiliControl quits.
    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: - Actions

    /// "Check for Updates…" — also how a waiting update gets shown.
    func checkForUpdates() {
        guard let controller = controller else { return }
        // An accessory app must come forward, or Sparkle's window opens
        // behind whatever you're using.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        lastCheck = updater.lastUpdateCheckDate
    }
}

// MARK: - SPUStandardUserDriverDelegate (gentle reminders)

extension UpdateController: SPUStandardUserDriverDelegate {

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Background check found an update: let Sparkle show it only if the
    /// app is already in focus (e.g. right after launch); otherwise we badge.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
