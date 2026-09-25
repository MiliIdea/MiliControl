//
//  NowPlaying.swift
//  MiliControl
//
//  What Spotify or Apple Music is playing, for the notch player.
//
//  Both apps announce every change themselves (distributed notifications:
//  play, pause, next track), so nothing is polled. Artwork, the playback
//  position and the transport buttons go through each app's official
//  scripting interface — macOS asks once per app ("MiliControl wants to
//  control Spotify"). A player that isn't running is never launched.
//
//  (macOS 15.4 closed the private "system now playing" API to other apps,
//  which is why this talks to the two players directly.)
//

import AppKit
import Combine
import os

struct Track: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    /// Seconds; 0 when unknown.
    let duration: TimeInterval
}

enum MusicPlayer: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var bundleID: String { rawValue }
    /// The name AppleScript addresses.
    var scriptName: String { self == .spotify ? "Spotify" : "Music" }

    fileprivate var notification: Notification.Name {
        Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged"
                                            : "com.apple.Music.playerInfo")
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

final class NowPlaying: ObservableObject {

    @Published private(set) var player: MusicPlayer?
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// Average colour of the artwork — tints the wave and progress bar.
    @Published private(set) var tint: NSColor?

    /// Where playback was at `positionDate` (the view extrapolates).
    private(set) var position: TimeInterval = 0
    private(set) var positionDate = Date()

    private let script = DispatchQueue(label: "com.mili.MiliControl.nowplaying.script", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    private var artworkTrackID: String?
    private let log = Logger(subsystem: "com.mili.MiliControl", category: "nowplaying")

    /// Current playback position, extrapolated while playing.
    func currentPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return position }
        let value = position + date.timeIntervalSince(positionDate)
        return track.map { $0.duration > 0 ? min(value, $0.duration) : value } ?? value
    }

    // MARK: - Start / stop

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            observers.append(center.addObserver(forName: player.notification, object: nil, queue: .main) {
                [weak self] note in self?.handle(note.userInfo ?? [:], from: player)
            })
        }
        // A player quitting sends no "stopped" notification of its own.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let self = self, let id = app?.bundleIdentifier, id == self.player?.bundleID else { return }
                self.clear()
            })
        // Already playing when MiliControl starts.
        for player in MusicPlayer.allCases where player.isRunning { query(player) }
    }

    func stop() {
        observers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        clear()
    }

    // MARK: - Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    /// Brings the player app forward.
    func openPlayer() {
        guard let player = player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let player = player, player.isRunning else { return }
        // Feels instant; the player's own notification confirms a moment later.
        if command == "playpause" { setPlaying(!isPlaying, at: currentPosition()) }
        run("tell application \"\(player.scriptName)\" to \(command)") { _ in }
    }

    // MARK: - Updates

    private func handle(_ info: [AnyHashable: Any], from source: MusicPlayer) {
        let state = info["Player State"] as? String ?? ""
        let playing = state == "Playing"

        // Another player pausing never takes over from one that's playing.
        if let current = player, current != source, isPlaying, !playing { return }

        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            if player == source { clear() }
            return
        }
        let durationMS = (info[source == .spotify ? "Duration" : "Total Time"] as? NSNumber)?.doubleValue ?? 0
        let id = (info["Track ID"] as? String) ?? (info["PersistentID"] as? NSNumber)?.stringValue
            ?? "\(title)|\(info["Artist"] as? String ?? "")"
        let track = Track(id: id, title: title,
                          artist: info["Artist"] as? String ?? "",
                          album: info["Album"] as? String ?? "",
                          duration: durationMS / 1000)
        apply(track, playing: playing, from: source)
        if let seconds = (info["Playback Position"] as? NSNumber)?.doubleValue {
            setPlaying(playing, at: seconds)
        } else {
            refreshPosition(source, playing: playing)
        }
    }

    private func apply(_ newTrack: Track, playing: Bool, from source: MusicPlayer) {
        if player != source { player = source }
        if track != newTrack { track = newTrack }
        if isPlaying != playing { isPlaying = playing }
        if artworkTrackID != newTrack.id { loadArtwork(for: newTrack, from: source) }
    }

    private func setPlaying(_ playing: Bool, at seconds: TimeInterval) {
        position = seconds
        positionDate = Date()
        if isPlaying != playing { isPlaying = playing }
        objectWillChange.send()
    }

    private func clear() {
        player = nil
        track = nil
        isPlaying = false
        artwork = nil
        tint = nil
        artworkTrackID = nil
        position = 0
    }

    /// Reads the whole state from a running player (at launch).
    private func query(_ source: MusicPlayer) {
        let name = source.scriptName
        let durationFactor = source == .spotify ? "/ 1000" : ""
        let lines = """
        tell application "\(name)"
            if player state is stopped then return ""
            set t to current track
            return (player state as string) & "\\n" & (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & ((((duration of t) \(durationFactor))) as string) & "\\n" & (player position as string)
        end tell
        """
        run(lines) { [weak self] result in
            guard let parts = result?.stringValue?.components(separatedBy: "\n"), parts.count >= 6,
                  let self = self, self.track == nil else { return }
            let playing = parts[0] == "playing"
            let track = Track(id: "\(parts[1])|\(parts[2])", title: parts[1], artist: parts[2], album: parts[3],
                              duration: Self.number(parts[4]))
            self.apply(track, playing: playing, from: source)
            self.setPlaying(playing, at: Self.number(parts[5]))
        }
    }

    private func refreshPosition(_ source: MusicPlayer, playing: Bool) {
        run("tell application \"\(source.scriptName)\" to player position") { [weak self] result in
            guard let self = self, self.player == source else { return }
            self.setPlaying(playing, at: result.map { Self.number($0.stringValue ?? "") } ?? 0)
        }
    }

    // MARK: - Artwork

    private func loadArtwork(for track: Track, from source: MusicPlayer) {
        artworkTrackID = track.id
        switch source {
        case .spotify:
            run("tell application \"Spotify\" to artwork url of current track") { [weak self] result in
                guard let text = result?.stringValue, let url = URL(string: text) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self?.setArtwork(image, for: track.id) }
                }.resume()
            }
        case .music:
            run("tell application \"Music\" to raw data of artwork 1 of current track") { [weak self] result in
                guard let data = result?.data, let image = NSImage(data: data) else {
                    self?.setArtwork(nil, for: track.id)
                    return
                }
                self?.setArtwork(image, for: track.id)
            }
        }
    }

    private func setArtwork(_ image: NSImage?, for trackID: String) {
        guard track?.id == trackID else { return }      // a newer track arrived meanwhile
        artwork = image
        tint = image.flatMap(Self.averageColor)
    }

    /// The artwork's average colour, brightened so it reads on black.
    private static func averageColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let hsb = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(hue: hsb.hueComponent,
                       saturation: min(1, hsb.saturationComponent * 1.2),
                       brightness: max(0.75, hsb.brightnessComponent),
                       alpha: 1)
    }

    // MARK: - AppleScript

    /// Runs a script off the main thread; the completion runs on main.
    /// Never launches a player: callers only address running ones.
    private func run(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        let log = self.log
        script.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error = error {
                log.debug("AppleScript failed: \(String(describing: error[NSAppleScript.errorMessage]), privacy: .public)")
            }
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }

    /// AppleScript numbers may use the locale's decimal comma.
    private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }
}
