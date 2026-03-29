import SwiftUI
import UIKit

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var downloadQueue: DownloadQueueStore

    @State private var showingResetDownloadsPrompt = false
    @State private var showingClearProgressPrompt = false
    @State private var importText = ""
    @State private var showingImportSheet = false
    @State private var showingExportSheet = false
    @State private var exportText = ""
    @State private var connectionStatus: String?
    @State private var newCollectionName = ""

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                downloadsSection
                downloadQueueSection
                offlineManagementSection
                readerSection
                appearanceSection
                collectionsSection
                networkSection
                privacySection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                importProgressSheet
            }
            .sheet(isPresented: $showingExportSheet) {
                exportProgressSheet
            }
            .alert("Remove all offline downloads?", isPresented: $showingResetDownloadsPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Remove All", role: .destructive) {
                    try? offlineLibrary.removeAllDownloads()
                }
            } message: {
                Text("This will delete all downloaded chapters from device storage.")
            }
            .alert("Clear all reading progress?", isPresented: $showingClearProgressPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    readingProgress.clearAllProgress()
                }
            }
        }
    }

    private var downloadsSection: some View {
        Section("Downloads") {
            Toggle("Wi-Fi only downloads", isOn: $settings.wifiOnlyDownloads)

            Stepper(value: $settings.autoDeleteReadAfterDays, in: 0...90) {
                if settings.autoDeleteReadAfterDays == 0 {
                    Text("Auto-delete read chapters: Off")
                } else {
                    Text("Auto-delete read chapters: \(settings.autoDeleteReadAfterDays) days")
                }
            }

            HStack {
                Text("Total offline storage")
                Spacer()
                Text(byteFormatter.string(fromByteCount: offlineLibrary.totalOfflineBytes()))
                    .foregroundStyle(.secondary)
            }

            ForEach(offlineLibrary.downloadedSeriesStorageSummaries()) { summary in
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                    Text("\(summary.chapterCount) chapters downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .overlay(alignment: .trailing) {
                    Text(byteFormatter.string(fromByteCount: summary.totalBytes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var offlineManagementSection: some View {
        Section("Offline Library Management") {
            ForEach(offlineLibrary.downloadedSeriesStorageSummaries()) { summary in
                Button(role: .destructive) {
                    try? offlineLibrary.removeDownloads(forSeriesID: summary.id)
                } label: {
                    Text("Remove \(summary.title) downloads")
                }
            }

            if !offlineLibrary.downloadedSeriesStorageSummaries().isEmpty {
                Button(role: .destructive) {
                    showingResetDownloadsPrompt = true
                } label: {
                    Text("Remove all offline content")
                }
            }
        }
    }

    private var downloadQueueSection: some View {
        Section("Download Queue") {
            if downloadQueue.items.isEmpty {
                Text("No queued downloads")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(downloadQueue.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.volumeTitle)
                        Text(queueStatusText(item.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Clear completed") {
                    downloadQueue.removeCompleted()
                }

                if downloadQueue.failedCount > 0 {
                    Button("Retry failed (\(downloadQueue.failedCount))") {
                        downloadQueue.retryFailed()
                    }
                }
            }
        }
    }

    private var readerSection: some View {
        Section("Reader") {
            Picker("Reading direction", selection: $settings.readerDirection) {
                ForEach(ReaderDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }

            Picker("Default zoom", selection: $settings.readerZoomMode) {
                ForEach(ReaderZoomMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
            Toggle("Show reader debug overlay", isOn: $settings.showReaderDebugOverlay)

            VStack(alignment: .leading, spacing: 6) {
                Text("Metadata text size")
                Slider(value: $settings.metadataTextScale, in: 0.8...1.4, step: 0.1)
                Text("\(Int(settings.metadataTextScale * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.selectedTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
        }
    }

    private var collectionsSection: some View {
        Section("Collections") {
            HStack(spacing: 8) {
                TextField("New collection name", text: $newCollectionName)
                Button("Add") {
                    settings.addCollection(named: newCollectionName)
                    newCollectionName = ""
                }
                .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if settings.collectionNames.isEmpty {
                Text("No collections yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.collectionNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(role: .destructive) {
                            settings.removeCollection(named: name)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private var networkSection: some View {
        Section("Network / Server") {
            TextField("Server URL", text: $settings.serverURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Toggle("Use local network only", isOn: $settings.localNetworkOnly)

            Button("Test connection") {
                Task {
                    let testingAPI = MangaAPI(baseURL: settings.serverURL)
                    do {
                        let result = try await testingAPI.fetchSeries()
                        connectionStatus = "Connected. Found \(result.count) series."
                    } catch {
                        connectionStatus = testingAPI.userFacingErrorMessage(for: error)
                    }
                }
            }

            if let connectionStatus {
                Text(connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        Section("Data / Privacy") {
            Button("Export reading progress") {
                exportText = readingProgress.exportJSONString() ?? "{}"
                showingExportSheet = true
            }

            Button("Import reading progress") {
                importText = ""
                showingImportSheet = true
            }

            Button(role: .destructive) {
                showingClearProgressPrompt = true
            } label: {
                Text("Clear reading history")
            }
        }
    }

    private var importProgressSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Paste exported JSON to import reading progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 4)
            }
            .padding()
            .navigationTitle("Import Progress")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingImportSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        _ = readingProgress.importFromJSONString(importText)
                        showingImportSheet = false
                    }
                }
            }
        }
    }

    private var exportProgressSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Copy this JSON to back up your progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: .constant(exportText))
                    .font(.system(.body, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 4)
                    .disabled(true)

                Button("Copy to Clipboard") {
                    UIPasteboard.general.string = exportText
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Export Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingExportSheet = false }
                }
            }
        }
    }

    private func queueStatusText(_ status: DownloadQueueStore.Status) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .downloading(let completed, let total):
            return "Downloading \(completed)/\(total)"
        case .completed:
            return "Completed"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
