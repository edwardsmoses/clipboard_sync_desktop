//
//  ContentView.swift
//  clipboard_sync_desktop
//
//  Created by Edwards Moses on 08/10/2025.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selection: ClipboardEntry.ID?
    @State private var searchQuery = ""
    @State private var isPairSheetPresented = false

    // History filtering now lives inside HistoryTab so the list reacts immediately to store changes.

    var body: some View {
        TabView {
            PairingTab(
                viewModel: viewModel,
                isDiscoverable: Binding(
                    get: { viewModel.isDiscoverable },
                    set: { viewModel.setDiscoverable($0) }
                ),
                onPair: { isPairSheetPresented = true }
            )
            .tabItem { Label("Devices", systemImage: "ipad.and.iphone") }

            HistoryTab(
                viewModel: viewModel,
                selection: $selection,
                searchQuery: $searchQuery,
                onTogglePin: viewModel.togglePin,
                onDelete: viewModel.delete
            )
            .tabItem { Label("History", systemImage: "clock") }
        }
        .sheet(isPresented: $isPairSheetPresented) {
            PairingSheet(
                endpoint: viewModel.pairingEndpoint,
                pairingCode: viewModel.pairingCode,
                networkSummary: viewModel.networkSummary
            )
        }
        .onAppear { viewModel.start() }
    }
}

private struct PairingTab: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isDiscoverable: Bool
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

                

                VStack(alignment: .leading, spacing: 4) {
                    Text("ClipBridge")
                        .font(.headline)
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
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
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
    private var pinnedEntries: [ClipboardEntry] { filteredEntries.filter(\.isPinned) }
    private var recentEntries: [ClipboardEntry] { filteredEntries.filter { !$0.isPinned } }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    SearchCard(
                        query: $searchQuery,
                        totalCount: allEntries.count,
                        filteredCount: filteredEntries.count
                    )
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if !pinnedEntries.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedEntries) { entry in
                            NavigationLink(value: entry.id) {
                                EntryRow(entry: entry, onTogglePin: onTogglePin, onDelete: onDelete)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                Section("Recent") {
                    if recentEntries.isEmpty {
                        Text("Copy something to see it here.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(recentEntries) { entry in
                        NavigationLink(value: entry.id) {
                            EntryRow(entry: entry, onTogglePin: onTogglePin, onDelete: onDelete)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Clipboard vault")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Delete all", systemImage: "trash")
                    }
                    .disabled(allEntries.isEmpty)
                }
            }
            .confirmationDialog("Delete all history?", isPresented: $showClearConfirm) {
                Button("Delete all", role: .destructive) {
                    viewModel.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(for: ClipboardEntry.ID.self) { id in
                if let entry = viewModel.historyStore.entries.first(where: { $0.id == id }) {
                    EntryDetailView(entry: entry)
                } else {
                    Text("Item not found").foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct HeroCard: View {
    let status: StatusDescriptor
    let entryCount: Int
    let filteredCount: Int
    let networkDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clipboard vault")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text("Your snippets stay in sync across devices. Tap a card to preview or copy instantly.")
                .foregroundStyle(Color.white.opacity(0.9))
                .font(.system(size: 15))

            HStack(spacing: 12) {
                StatusChip(label: status.label, tint: status.tint)
                StatusChip(label: "\(entryCount) saved", tint: Color.white.opacity(0.2), contentColor: .white)
                StatusChip(label: networkDescription, tint: Color.white.opacity(0.18), contentColor: .white)
            }

            if filteredCount != entryCount {
                Text("\(filteredCount) results match your search")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1d4ed8), Color(hex: 0x1e40af)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(32)
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 14)
    }
}

private struct PairingCard: View {
    let networkSummary: NetworkSummary
    var isDiscoverable: Binding<Bool>
    let endpoint: String?
    var onPair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pair a device")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                Label(networkSummary.description, systemImage: networkSummary.isConnected ? "wifi" : "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(networkSummary.isConnected ? Color(hex: 0x2563eb) : Color.red)
                Text(networkSummary.isConnected
                    ? "Secure relay codes route through bridge.edwardsmoses.com so phones can pair from anywhere."
                    : "Connect this Mac to the internet to mint a new pairing code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: isDiscoverable) {
                Text("Allow this Mac to be discoverable on the network")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            HStack {
                Button(action: onPair) {
                    Label("Show pairing code", systemImage: "number.square")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x2563eb))

                if endpoint == nil {
                    Text("Bridge is starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Keep this window open until you finish entering the code on your phone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find saved snippets…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
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

private struct EntryRow: View {
    let entry: ClipboardEntry
    var onTogglePin: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                IconBadge(contentType: entry.contentType)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.deviceName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

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

            Text(entry.preview.isEmpty ? "No preview available" : entry.preview)
                .font(.system(size: 14))
                .lineLimit(3)

            HStack(spacing: 8) {
                StatusTag(text: entry.isPinned ? "Pinned" : "Pin", tint: Color.gray.opacity(0.15), contentColor: .secondary)
                    .onTapGesture {
                        onTogglePin(entry)
                    }
                StatusTag(text: entry.syncState.rawValue.capitalized, tint: Color(hex: 0xe5e7eb), contentColor: Color(hex: 0x1f2937))
                StatusTag(text: entry.contentType.rawValue.capitalized, tint: Color(hex: 0xf1f5f9), contentColor: Color(hex: 0x0f172a))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") {
                onTogglePin(entry)
            }
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
        }
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
    var contentColor: Color = .black

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint)
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
                .foregroundStyle(Color(hex: 0x2563eb))
            VStack(alignment: .leading) {
                Text(client.deviceName)
                    .font(.subheadline)
                Text("Live connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(Color(hex: 0x2563eb))

            Text("Pair your phone")
                .font(.title3.bold())

            Text("Keep this window open, then tap “Pair new device” on your phone to join via the secure relay.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button(action: onPair) {
                Label("Show pairing code", systemImage: "number.square")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x2563eb))

            HStack(spacing: 8) {
                Image(systemName: networkSummary.isConnected ? "wifi" : "wifi.slash")
                    .foregroundStyle(networkSummary.isConnected ? Color.green : Color.red)
                Text(networkSummary.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(Color(hex: 0x2563eb))
            Text("Select a clipboard item")
                .font(.title3.bold())
            Text("Choose a card from the left to inspect the full content, metadata, and sync status.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
