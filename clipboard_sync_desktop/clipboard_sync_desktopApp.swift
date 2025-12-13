//
//  clipboard_sync_desktopApp.swift
//  clipboard_sync_desktop
//
//  Created by Edwards Moses on 08/10/2025.
//

import AppKit
import SwiftUI

@main
struct clipboard_sync_desktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    init() {
        appDelegate.viewModel = viewModel
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    weak var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let viewModel else { return }
        statusItemController.attach(viewModel: viewModel)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }
}
