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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    appDelegate.bind(viewModel: viewModel)
                }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    weak var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let viewModel {
            statusItemController.attach(viewModel: viewModel)
            viewModel.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }

    func bind(viewModel: AppViewModel) {
        // Only bind once to avoid duplicate status items.
        guard self.viewModel == nil else { return }
        self.viewModel = viewModel
        statusItemController.attach(viewModel: viewModel)
        viewModel.start()
    }
}
