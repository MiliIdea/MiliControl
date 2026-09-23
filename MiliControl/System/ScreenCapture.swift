//
//  ScreenCapture.swift
//  MiliControl
//
//  Takes a small screenshot of a display — what's on the desktop you are on
//  right now. (macOS never exposes the contents of other desktops.)
//
//  • macOS 14+: ScreenCaptureKit, excluding MiliControl's own windows, so the
//    HUD or editor never end up inside a preview.
//  • macOS 13:  CGDisplayCreateImage (callers avoid capturing while
//    MiliControl's overlays are on screen).
//
//  Both need Screen Recording permission.
//

import AppKit
import ScreenCaptureKit

enum ScreenCapture {

    /// Whether Screen Recording is granted (never prompts).
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's Screen Recording prompt (first time only).
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// The display a desktop lives on, from the window server's
    /// "Display Identifier" ("Main" when displays share Spaces, otherwise the
    /// display's UUID). Falls back to the main display.
    static func displayID(forIdentifier identifier: String) -> CGDirectDisplayID {
        guard identifier != "Main" else { return CGMainDisplayID() }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return CGMainDisplayID() }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return CGMainDisplayID() }
        for display in displays {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { continue }
            let string = CFUUIDCreateString(nil, uuid) as String
            if string.caseInsensitiveCompare(identifier) == .orderedSame { return display }
        }
        return CGMainDisplayID()
    }

    /// Captures `display` scaled to `width` pixels wide.
    /// `completion` is called on the main queue.
    static func capture(display: CGDirectDisplayID, width: Int, completion: @escaping (CGImage?) -> Void) {
        let finish: (CGImage?) -> Void = { image in
            DispatchQueue.main.async { completion(image) }
        }
        if #available(macOS 14.0, *) {
            captureWithScreenCaptureKit(display: display, width: width, completion: finish)
        } else {
            finish(captureWithCoreGraphics(display: display, width: width))
        }
    }

    // MARK: - macOS 14+

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit(display displayID: CGDirectDisplayID, width: Int,
                                                    completion: @escaping (CGImage?) -> Void) {
        // All windows (not just on-screen ones) so MiliControl itself is
        // always listed and can be excluded.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, _ in
            guard let content = content,
                  let display = content.displays.first(where: { $0.displayID == displayID })
                                ?? content.displays.first else {
                completion(nil)
                return
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownPID }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = max(1, Int(Double(width) * Double(display.height) / Double(max(display.width, 1))))
            configuration.showsCursor = false

            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                completion(image)
            }
        }
    }

    // MARK: - macOS 13

    private static func captureWithCoreGraphics(display: CGDirectDisplayID, width: Int) -> CGImage? {
        // CGDisplayCreateImage is obsoleted in newer SDKs (it only runs here on
        // macOS 13), so it's looked up at runtime instead of linked directly.
        typealias CreateImage = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)          // RTLD_DEFAULT
        guard let symbol = dlsym(defaultHandle, "CGDisplayCreateImage"),
              let full = unsafeBitCast(symbol, to: CreateImage.self)(display)?.takeRetainedValue()
        else { return nil }
        return downscale(full, toWidth: width)
    }

    private static func downscale(_ image: CGImage, toWidth width: Int) -> CGImage? {
        guard image.width > width else { return image }
        let height = max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
