//
//  ContentView.swift
//  clipboard_sync_desktop
//
//  Created by Edwards Moses on 08/10/2025.
//

import AppKit
import SwiftUI

private enum Palette {
    static let background = Color(hex: 0xf6f7fb)
    static let surface = Color.white
    static let surfaceBorder = Color.black.opacity(0.06)
    static let accent = Color(hex: 0x4f8cff)
    static let mutedText = Color(hex: 0x64748b)
    static let primaryText = Color(hex: 0x0f172a)
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selection: ClipboardEntry.ID?
    @State private var searchQuery = ""
    @State private var isPairSheetPresented = false
    @State private var tabSelection: Tab = .devices

    var body: some View {
        VStack(spacing: 0) {
            TopBar(tabSelection: $tabSelection, onAction: {
                if tabSelection == .history {
                    viewModel.deleteAll()
                } else {
                    isPairSheetPresented = true
                }
            })
            StatusRow(
                state: viewModel.syncServer.state,
                entryCount: viewModel.historyStore.entries.count,
                networkDescription: viewModel.networkSummary.description
            )
            Divider().overlay(Palette.surfaceBorder).padding(.horizontal, 0)
            TabView(selection: $tabSelection) {
                PairingTab(
                    viewModel: viewModel,
                    isDiscoverable: Binding(
                        get: { viewModel.isDiscoverable },
                        set: { viewModel.setDiscoverable($0) }
                    ),
                    startAtLogin: Binding(
                        get: { viewModel.startAtLoginEnabled },
                        set: { viewModel.setStartAtLoginEnabled($0) }
                    ),
                    showStatusItem: Binding(
                        get: { viewModel.showStatusItem },
                        set: { viewModel.setShowStatusItem($0) }
                    ),
                    onPair: { isPairSheetPresented = true }
                )
                .tag(Tab.devices)
                .tabItem { EmptyView() }

                HistoryTab(
                    viewModel: viewModel,
                    selection: $selection,
                    searchQuery: $searchQuery,
                    onTogglePin: viewModel.togglePin,
                    onDelete: viewModel.delete
                )
                .tag(Tab.history)
                .tabItem { EmptyView() }
            }
            .tabViewStyle(.automatic)
        }
        .sheet(isPresented: $isPairSheetPresented) {
            PairingSheet(
                endpoint: viewModel.pairingEndpoint,
                pairingCode: viewModel.pairingCode,
                networkSummary: viewModel.networkSummary
            )
        }
        .background(Palette.background)
        .onAppear { viewModel.start() }
    }
}

private struct PairingTab: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isDiscoverable: Bool
    @Binding var startAtLogin: Bool
    @Binding var showStatusItem: Bool
    var onPair: () -> Void

    private var statusDescriptor: StatusDescriptor {
        switch viewModel.syncServer.state {
        case .stopped:
            return .init(label: "Stopped", tint: Color(nsColor: .systemGray))
        case .connecting:
            return .init(label: "Connecting…", tint: Color(hex: 0xf59e0b))
        case .connected:
            return isDiscoverable ? .init(label: "Discoverable", tint: Color(hex: 0x4ade80)) : .init(label: "Hidden", tint: Color(hex: 0xfbbf24))
        case .failed:
            return .init(label: "Error", tint: Color(hex: 0xf87171))
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusStrip(
                    status: statusDescriptor,
                    entryCount: viewModel.historyStore.entries.count,
                    networkDescription: viewModel.networkSummary.description,
                    clients: viewModel.syncServer.clients
                )
                .frame(maxWidth: .infinity)

                PairingCard(
                    networkSummary: viewModel.networkSummary,
                    isDiscoverable: $isDiscoverable,
                    endpoint: viewModel.pairingEndpoint,
                    onPair: onPair
                )
                .frame(maxWidth: .infinity)

                DesktopBehaviorCard(
                    startAtLogin: $startAtLogin,
                    showStatusItem: $showStatusItem,
                    startAtLoginAvailable: LaunchAtLoginManager.isAvailable,
                    isWatching: viewModel.isWatching,
                    onToggleWatching: { viewModel.isWatching ? viewModel.stop() : viewModel.start() }
                )
                .frame(maxWidth: .infinity)



                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("ClipBridge")
                            .font(.headline)
                        Text(appVersion)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    Text("Built by Edwards Moses · edwardsmoses.com")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
    }
}

private struct StatusStrip: View {
    let status: StatusDescriptor
    let entryCount: Int
    let networkDescription: String
    let clients: [SyncClientInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusChip(label: status.label, tint: status.tint, contentColor: .white)
                StatusChip(label: "\(entryCount) saved", tint: Color.gray.opacity(0.15), contentColor: .secondary)
                StatusChip(label: networkDescription, tint: Color.gray.opacity(0.15), contentColor: .secondary)
                if !clients.isEmpty {
                    StatusChip(label: "\(clients.count) connected", tint: Color.gray.opacity(0.15), contentColor: .secondary)
                }
                Spacer()
            }

            if !clients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clients) { client in
                            StatusChip(label: client.deviceName, tint: Color.gray.opacity(0.12), contentColor: .secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.surfaceBorder)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)
        )
    }
}

private struct DesktopBehaviorCard: View {
    @Binding var startAtLogin: Bool
    @Binding var showStatusItem: Bool
    let startAtLoginAvailable: Bool
    let isWatching: Bool
    var onToggleWatching: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desktop controls")
                        .font(.headline)
                    Text("Keep ClipBridge always on. Launch at login and keep the menu bar shortcut visible for quick access.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    onToggleWatching()
                } label: {
                    Label(isWatching ? "Pause" : "Resume", systemImage: isWatching ? "pause.fill" : "play.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $startAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start on login")
                            .font(.subheadline.weight(.semibold))
                        Text("Launches the helper automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!startAtLoginAvailable)
                .overlay(alignment: .trailing) {
                    if !startAtLoginAvailable {
                        Text("Requires macOS 13+")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $showStatusItem) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show menu bar icon")
                            .font(.subheadline.weight(.semibold))
                        Text("Keeps a menu bar shortcut with quick actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        )
    }
}

private struct HistoryTab: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: ClipboardEntry.ID?
    @Binding var searchQuery: String
    var onTogglePin: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void

    @State private var showClearConfirm = false

    private var allEntries: [ClipboardEntry] { viewModel.historyStore.entries }
    private var filteredEntries: [ClipboardEntry] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allEntries }
        let needle = trimmed.lowercased()
        return allEntries.filter { $0.preview.lowercased().contains(needle) || $0.deviceName.lowercased().contains(needle) }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                SearchHeader(
                    query: $searchQuery,
                    totalCount: allEntries.count,
                    filteredCount: filteredEntries.count
                )
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(filteredEntries) { entry in
                            HistoryGridRow(entry: entry, onTogglePin: onTogglePin, onDelete: onDelete, onSelect: {
                                selection = entry.id
                            })
                            Divider().padding(.leading, 64)
                        }
                    }
                    .frame(maxWidth: 920)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(Palette.background)
            }

            DetailsDrawer(
                entry: selection.flatMap { id in viewModel.historyStore.entries.first(where: { $0.id == id }) },
                onClose: { selection = nil },
                onCopy: { entry in
                    if let text = entry.text, !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                },
                onDelete: { entry in
                    onDelete(entry)
                    selection = nil
                }
            )
        }
    }
}

private struct SearchHeader: View {
    @Binding var query: String
    let totalCount: Int
    let filteredCount: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.mutedText)
                TextField("Search your clipboard", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.surfaceBorder)
                    )
            )

            Spacer()
            StatusChip(label: "\(filteredCount) saved", tint: Palette.accent.opacity(0.12), contentColor: Palette.primaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Palette.background)
    }
}

private struct HeroCard: View {
    let status: StatusDescriptor
    let entryCount: Int
    let filteredCount: Int
    let networkDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ClipBridge")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.primaryText)

            Text("Subtle, production-ready clipboard sync for every device. Tap to preview or reuse instantly.")
                .foregroundStyle(Palette.primaryText.opacity(0.85))
                .font(.system(size: 14))

            HStack(spacing: 12) {
                StatusChip(label: status.label, tint: Palette.accent.opacity(0.12), contentColor: Palette.primaryText)
                StatusChip(label: "\(entryCount) saved", tint: Palette.accent.opacity(0.12), contentColor: Palette.primaryText)
                StatusChip(label: networkDescription, tint: Palette.accent.opacity(0.1), contentColor: Palette.primaryText.opacity(0.9))
            }

            if filteredCount != entryCount {
                Text("\(filteredCount) results match your search")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText.opacity(0.7))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.surfaceBorder)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
    }
}

private struct PairingCard: View {
    let networkSummary: NetworkSummary
    var isDiscoverable: Binding<Bool>
    let endpoint: String?
    var onPair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair a device")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.primaryText)

            Text("Securely pair with a one-time code.")
                .font(.subheadline)
                .foregroundStyle(Palette.mutedText)

            HStack {
                Text("Allow this Mac to be discoverable")
                    .font(.subheadline)
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                Toggle("", isOn: isDiscoverable)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            Button(action: onPair) {
                Label("Show pairing code", systemImage: "number.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)

            Text(endpoint == nil ? "Bridge is starting…" : "Keep this window open until you finish entering the code on your phone.")
                .font(.caption)
                .foregroundStyle(Palette.mutedText)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Palette.surfaceBorder)
                )
        )
    }
}

private struct SearchCard: View {
    @Binding var query: String
    let totalCount: Int
    let filteredCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search history")
                .font(.headline)
                .foregroundStyle(Palette.primaryText)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.mutedText)
                TextField("Find saved snippets…", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.primaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Palette.surfaceBorder)
                    )
            )

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(Palette.mutedText)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Palette.surfaceBorder)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        )
    }

    private var summaryText: String {
        if query.isEmpty {
            return "\(totalCount) item\(totalCount == 1 ? "" : "s") stored locally."
        }
        let pluralSuffix = filteredCount == 1 ? "" : "es"
        return "\(filteredCount) match\(pluralSuffix) for “\(query)”."
    }
}

private struct HistoryGridRow: View {
    let entry: ClipboardEntry
    var onTogglePin: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconBadge(contentType: entry.contentType)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(entry.preview.isEmpty ? "No preview available" : entry.preview)
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .foregroundStyle(Palette.primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedText)
                Menu {
                    Button(entry.isPinned ? "Unpin" : "Pin") {
                        onTogglePin(entry)
                    }
                    Button("Delete", role: .destructive) {
                        onDelete(entry)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .fixedSize()
            }
            .frame(width: 140, alignment: .trailing)
        }
        .frame(minHeight: 72)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

private struct EntryDetailView: View {
    let entry: ClipboardEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let text = entry.text, !text.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Content")
                            .font(.headline)
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .modifier(DetailCardStyle())
                }

                if let imageData = entry.imageData, let image = NSImage(data: imageData) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image")
                            .font(.headline)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(16)
                            .shadow(radius: 8)
                    }
                    .modifier(DetailCardStyle())
                }

                metadata
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.deviceName)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(entry.createdAt.formatted(date: .complete, time: .standard))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                StatusTag(text: entry.contentType.rawValue.capitalized, tint: Color(hex: 0xf1f5f9), contentColor: Color(hex: 0x0f172a))
                StatusTag(text: entry.syncState.rawValue.capitalized, tint: Color(hex: 0xe5e7eb), contentColor: Color(hex: 0x1f2937))
                if entry.isPinned {
                    StatusTag(text: "Pinned", tint: Color(hex: 0xfbbf24), contentColor: .black)
                }
            }

            if let text = entry.text, !text.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy text to clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x2563eb))
            }
        }
        .modifier(DetailCardStyle())
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Entry ID")
                        .fontWeight(.semibold)
                    Text(entry.id.uuidString)
                        .font(.body.monospacedDigit())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Device ID")
                        .fontWeight(.semibold)
                    Text(entry.deviceId)
                        .font(.body.monospacedDigit())
                        .textSelection(.enabled)
                }
                if let syncedAt = entry.syncedAt {
                    GridRow {
                        Text("Synced")
                            .fontWeight(.semibold)
                        Text(syncedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let metadata = entry.metadata, !metadata.isEmpty {
                    ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        GridRow {
                            Text(key.capitalized)
                                .fontWeight(.semibold)
                            Text(value)
                        }
                    }
                }
            }
        }
        .modifier(DetailCardStyle())
    }
}

private struct DetailCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 8)
            )
    }
}

private struct DetailsDrawer: View {
    let entry: ClipboardEntry?
    var onClose: () -> Void
    var onCopy: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture { onClose() }
                    drawer(entry: entry)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: entry?.id)
    }

    private func drawer(entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.deviceName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Palette.mutedText)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if let text = entry.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.headline)
                    Text(text)
                        .font(.body)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onCopy(entry)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)

                Button(role: .destructive) {
                    onDelete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Metadata")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Entry ID: \(entry.id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedText)
                    Text("Type: \(entry.contentType.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedText)
                    Text("Sync: \(entry.syncState.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedText)
                    if entry.isPinned {
                        Text("Pinned")
                            .font(.caption)
                            .foregroundStyle(Palette.mutedText)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.surfaceBorder)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .vertical)
    }
}

private struct IconBadge: View {
    let contentType: ClipboardContentType

    var body: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.12))
                .frame(width: 28, height: 28)
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch contentType {
        case .text:
            return "text.alignleft"
        case .html:
            return "curlybraces"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .unknown:
            return "questionmark"
        }
    }

    private var iconColor: Color {
        switch contentType {
        case .text:
            return Color(hex: 0x2563eb)
        case .html:
            return Color(hex: 0x0ea5e9)
        case .image:
            return Color(hex: 0x22c55e)
        case .file:
            return Color(hex: 0xf97316)
        case .unknown:
            return Color(hex: 0x6b7280)
        }
    }
}

private struct StatusTag: View {
    let text: String
    let tint: Color
    var contentColor: Color = Palette.primaryText

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint.opacity(0.35))
            )
            .foregroundStyle(contentColor)
    }
}

private struct StatusChip: View {
    let label: String
    let tint: Color
    var contentColor: Color = .black

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(contentColor == .white ? Color.white.opacity(0.8) : tint.opacity(0.9))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tint)
        )
        .foregroundStyle(contentColor)
    }
}

private struct ConnectedDeviceRow: View {
    let client: SyncClientInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading) {
                Text(client.deviceName)
                    .font(.subheadline)
                    .foregroundStyle(Palette.primaryText)
                Text("Live connection")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedText)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PairingFocusView: View {
    let networkSummary: NetworkSummary
    var onPair: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Palette.accent)

            Text("Pair your phone")
                .font(.title3.bold())
                .foregroundStyle(Palette.primaryText)

            Text("Keep this window open, then tap “Pair new device” on your phone to join via the secure relay.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.mutedText)
                .frame(maxWidth: 360)

            Button(action: onPair) {
                Label("Show pairing code", systemImage: "number.square")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)

            HStack(spacing: 8) {
                Image(systemName: networkSummary.isConnected ? "wifi" : "wifi.slash")
                    .foregroundStyle(networkSummary.isConnected ? Color.green : Color.red)
                Text(networkSummary.description)
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(Palette.accent)
            Text("Select a clipboard item")
                .font(.title3.bold())
                .foregroundStyle(Palette.primaryText)
            Text("Choose a card from the left to inspect the full content, metadata, and sync status.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.mutedText)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PairingSheet: View {
    let endpoint: String?
    let pairingCode: String?
    let networkSummary: NetworkSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 6)

            Text("Pair with your phone")
                .font(.title2.weight(.semibold))

            if let code = pairingCode {
                PairingCodeDisplay(code: code)

                VStack(spacing: 8) {
                    Text("Enter this code on your phone. We’ll use it to autofill the secure connection.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Copy code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.replacingOccurrences(of: "-", with: ""), forType: .string)
                    }
                }
            } else {
                ProgressView("Preparing secure bridge…")
                    .progressViewStyle(.circular)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(networkSummary.description, systemImage: networkSummary.isConnected ? "wifi" : "wifi.slash")
                    .foregroundStyle(networkSummary.isConnected ? Color.green : Color.red)
                Text("Open Clipboard Sync on Android, choose “Pair new device,” and enter the code. The secure relay handles the rest — any network works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 420)
    }
}

private struct PairingCodeDisplay: View {
    let code: String

    private var groups: [String] {
        code
            .uppercased()
            .split(separator: "-")
            .map(String.init)
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(groups, id: \.self) { group in
                Text(group)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .kerning(4)
                    .frame(minWidth: 80)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusDescriptor {
    let label: String
    let tint: Color
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
private enum Tab: Hashable {
    case devices
    case history
}

private struct TopBar: View {
    @Binding var tabSelection: Tab
    var onAction: () -> Void

    var body: some View {
        HStack {
            Text("ClipBridge")
                .font(.headline)
                .foregroundStyle(Palette.primaryText)
            Spacer()
            SegmentedControl(selection: $tabSelection)
            Spacer()
            Button(action: onAction) {
                Image(systemName: tabSelection == .history ? "trash" : "number.square")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Palette.background)
    }
}

private struct SegmentedControl: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(title: "Devices", tab: .devices)
            segmentButton(title: "History", tab: .history)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.surfaceBorder)
                )
        )
    }

    private func segmentButton(title: String, tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minWidth: 96)
                .foregroundStyle(selection == tab ? Palette.primaryText : Palette.mutedText)
                .background(
                    Group {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.accent.opacity(0.12))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusRow: View {
    let state: SyncServer.ServerState
    let entryCount: Int
    let networkDescription: String

    private var statusText: String {
        switch state {
        case .stopped: return "Stopped"
        case .connecting: return "Connecting"
        case .connected: return "Syncing"
        case .failed: return "Error"
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return Color(hex: 0x22c55e)
        case .connecting: return Color(hex: 0xeab308)
        case .failed: return Color(hex: 0xf97316)
        case .stopped: return Palette.mutedText
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            StatusChip(label: "\(entryCount) saved", tint: Palette.accent.opacity(0.12), contentColor: Palette.primaryText)
            StatusChip(label: networkDescription, tint: Palette.accent.opacity(0.1), contentColor: Palette.primaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Palette.background)
    }
}
