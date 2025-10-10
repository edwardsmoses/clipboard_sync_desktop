//
//  clipboard_sync_desktopApp.swift
//  clipboard_sync_desktop
//
//  Created by Edwards Moses on 08/10/2025.
//

import SwiftUI

@main
struct clipboard_sync_desktopApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
