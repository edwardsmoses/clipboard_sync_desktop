//
//  LaunchAtLoginManager.swift
//  clipboard_sync_desktop
//
//  Created by Codex on 2025-02-16.
//

import Foundation
import ServiceManagement

/// Small helper for registering/unregistering the app as a login item.
enum LaunchAtLoginManager {
    static var isAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    static func isEnabled() -> Bool {
        guard isAvailable else { return false }
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[launch] Failed to update login item: \(String(describing: error))")
            }
        }
    }
}
