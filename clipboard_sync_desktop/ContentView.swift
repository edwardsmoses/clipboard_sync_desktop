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

    var body: some View {
        NavigationSplitView {
            HistoryListView(
                store: viewModel.historyStore,
                selection: $selection,
                onPin: viewModel.togglePin,
                onDelete: viewModel.delete
            )
            .navigationTitle("Clipboard history")
        } detail: {
            if let selection,
               let entry = viewModel.historyStore.entries.first(where: { $0.id == selection }) {
                EntryDetailView(entry: entry)
            } else {
                ContentUnavailableView("Select an entry", systemImage: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            viewModel.start()
        }
    }
}

struct HistoryListView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @Binding var selection: ClipboardEntry.ID?
    var onPin: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void

    var body: some View {
        List(selection: $selection) {
            let pinned = store.entries.filter { $0.isPinned }
            let recent = store.entries.filter { !$0.isPinned }

            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { entry in
                        HistoryRow(entry: entry, onPin: onPin, onDelete: onDelete)
                    }
                }
            }

            Section("Recent") {
                ForEach(recent) { entry in
                    HistoryRow(entry: entry, onPin: onPin, onDelete: onDelete)
                }
                .onDelete { indexSet in
                    indexSet.map { recent[$0] }.forEach(onDelete)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry
    var onPin: (ClipboardEntry) -> Void
    var onDelete: (ClipboardEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.preview.isEmpty ? "(empty)" : entry.preview)
                    .font(.headline)
                    .lineLimit(2)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                }
            }
            Text(entry.deviceName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") {
                onPin(entry)
            }
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
        }
    }
}

struct EntryDetailView: View {
    let entry: ClipboardEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.deviceName)
                    .font(.title2)
                    .bold()
                Text(entry.createdAt.formatted(date: .complete, time: .standard))
                    .foregroundStyle(.secondary)

                if let text = entry.text {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if let imageData = entry.imageData, let image = NSImage(data: imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata")
                        .font(.headline)
                    LabeledContent("Content type", value: entry.contentType.rawValue)
                    LabeledContent("Sync state", value: entry.syncState.rawValue)
                    if let syncedAt = entry.syncedAt {
                        LabeledContent("Synced at", value: syncedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Identifier", value: entry.id.uuidString)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
