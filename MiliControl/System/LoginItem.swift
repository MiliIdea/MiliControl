//
//  LoginItem.swift
//  MiliControl
//
//  "Launch at login" using ServiceManagement's SMAppService (macOS 13+).
//

import ServiceManagement
import os

enum LoginItem {

    private static let log = Logger(subsystem: "com.mili.MiliControl", category: "login-item")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message to show the user, or nil on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
