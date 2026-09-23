//
//  main.swift
//  MiliControl
//
//  Explicit NSApplication entry point: MiliControl is a menu-bar utility
//  that owns its own windows, so it doesn't use a SwiftUI App scene.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
