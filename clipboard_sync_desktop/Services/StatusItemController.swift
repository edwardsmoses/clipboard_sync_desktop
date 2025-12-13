//
//  StatusItemController.swift
//  clipboard_sync_desktop
//
//  Created by Codex on 2025-02-16.
//

import AppKit
import Combine

/// Drives the menu bar status item and quick actions.
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private weak var viewModel: AppViewModel?

    func attach(viewModel: AppViewModel) {
        self.viewModel = viewModel

        viewModel.$showStatusItem
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldShow in
                self?.setVisible(shouldShow)
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            viewModel.$startAtLoginEnabled.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isWatching.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$syncServer.map { _ in () }.eraseToAnyPublisher(),
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateMenu()
        }
        .store(in: &cancellables)

        setVisible(viewModel.showStatusItem)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.image = NSImage(
                        systemSymbolName: "doc.on.clipboard.fill",
                        accessibilityDescription: "ClipBridge"
                    )
                    button.image?.isTemplate = true
                    button.toolTip = "ClipBridge"
                }
                statusItem = item
            }
            updateMenu()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let header = NSMenuItem(title: "ClipBridge", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let openItem = NSMenuItem(title: "Open ClipBridge", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let isWatching = viewModel?.isWatching ?? false
        let toggleWatch = NSMenuItem(
            title: isWatching ? "Pause syncing" : "Resume syncing",
            action: #selector(toggleSyncing),
            keyEquivalent: ""
        )
        toggleWatch.target = self
        menu.addItem(toggleWatch)

        let startAtLoginItem = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginItem.state = (viewModel?.startAtLoginEnabled ?? false) ? .on : .off
        startAtLoginItem.target = self
        menu.addItem(startAtLoginItem)

        let menuBarItem = NSMenuItem(title: "Show menu bar icon", action: #selector(toggleStatusItemVisibility), keyEquivalent: "")
        menuBarItem.state = (viewModel?.showStatusItem ?? true) ? .on : .off
        menuBarItem.target = self
        menu.addItem(menuBarItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ClipBridge", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func toggleSyncing() {
        guard let vm = viewModel else { return }
        if vm.isWatching {
            vm.stop()
        } else {
            vm.start()
        }
    }

    @objc private func toggleStartAtLogin() {
        guard let vm = viewModel else { return }
        vm.setStartAtLoginEnabled(!vm.startAtLoginEnabled)
    }

    @objc private func toggleStatusItemVisibility() {
        guard let vm = viewModel else { return }
        vm.setShowStatusItem(!vm.showStatusItem)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
