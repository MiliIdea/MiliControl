//
//  CGSPrivate.swift
//  MiliControl
//
//  Read-only private window-server (SkyLight/CGS) calls. MiliControl only
//  *reads* Spaces with these — it never creates, destroys or switches Spaces
//  through private API. Switching goes through macOS's own "Switch to
//  Desktop N" shortcut (see DesktopSwitcher), which works without SIP changes.
//
//  These symbols are not in the public SDK and may change between macOS
//  releases. Everything that uses them is defensive about missing/odd data.
//

import Foundation
import CoreGraphics

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// One dictionary per display: "Display Identifier", "Current Space", and
/// "Spaces" (each with "ManagedSpaceID"/"id64", "type", "uuid").
/// Space `type` 0 = regular desktop, 4 = fullscreen app.
/// Optional: the window server may return NULL (e.g. before the app is fully
/// trusted); treating that as non-optional would crash at launch.
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray?

/// The space that currently has focus.
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: CGSConnectionID) -> CGSSpaceID

/// Window IDs living on the given spaces. `options` 0x2 = all owners.
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ connection: CGSConnectionID,
                                      _ owner: Int,
                                      _ spaces: CFArray,
                                      _ options: Int,
                                      _ setTags: UnsafeMutablePointer<UInt64>,
                                      _ clearTags: UnsafeMutablePointer<UInt64>) -> CFArray?
