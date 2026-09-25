//
//  AppFonts.swift
//  MiliControl
//
//  Fonts MiliControl brings with it (Resources/Fonts), registered for this
//  app only at launch — nothing is installed on the Mac.
//
//  Persian / Arabic-script text (the Shamsi and Hijri calendars) uses the
//  first family found, in order:
//    1. IRANSans (any edition) if it's installed on this Mac — it's a
//       commercial font, so it isn't bundled; install your own licensed copy
//       and MiliControl picks it up;
//    2. Vazirmatn — free (SIL Open Font License) and bundled;
//    3. SF Arabic — macOS's own Arabic-script sans;
//    4. Noto Sans Arabic.
//

import AppKit
import CoreText
import os

enum AppFonts {

    static let persianFamilies = [
        "IRANSansX", "IRANSansXFaNum", "IRANSans", "IRANSansFaNum", "IRANSans(FaNum)",
        "Vazirmatn", "SF Arabic", "Noto Sans Arabic",
    ]

    /// The bundled Vazirmatn face closest to `weight`, unless IRANSans is
    /// installed (it's preferred when present).
    static func vazirmatn(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let iranSansInstalled = NSFontManager.shared.availableFontFamilies
            .contains { $0.hasPrefix("IRANSans") }
        guard !iranSansInstalled else { return nil }
        let face: String
        switch weight.rawValue {
        case ..<NSFont.Weight.medium.rawValue: face = "Regular"
        case ..<NSFont.Weight.semibold.rawValue: face = "Medium"
        case ..<NSFont.Weight.bold.rawValue: face = "SemiBold"
        default: face = "Bold"
        }
        return NSFont(name: "Vazirmatn-\(face)", size: size)
    }

    /// Makes the bundled fonts available to MiliControl's own text.
    static func registerBundled() {
        let log = Logger(subsystem: "com.mili.MiliControl", category: "fonts")
        let urls = ["ttf", "otf"].flatMap {
            Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: "Fonts") ?? []
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                log.debug("Font not registered: \(url.lastPathComponent, privacy: .public)")
            }
        }
    }
}
