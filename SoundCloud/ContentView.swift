//
//  ContentView.swift
//  SoundCloud
//
//  Created by Romain on 2/6/25.
//  Edited by Jaufré on 2/11/25.
//

import SwiftUI
import os
import Foundation

func realUserHomeDirectory() -> String {
    if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
        return String(cString: home)
    }
    return NSHomeDirectory()
}

struct DownloadItem: Identifiable {
    enum Status { case downloading, completed, failed }
    let id = UUID()
    let url: URL
    var status: Status
    var progress: Double
    var fileName: String
    var process: Process? // Add this
}


import AppKit

func selectDirectory(completion: @escaping (URL?) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Select"
    panel.begin { response in
        if response == .OK {
            completion(panel.url)
        } else {
            completion(nil)
        }
    }
}



struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var debugMessages: [String] = []
    @State private var showDownloadsPopover = false
    @State private var showDebugPopover = false
    @State private var downloadURLString: String = "" // Single source for URL
    @State private var downloads: [DownloadItem] = []
    @State private var downloadDirectory: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Music/downloaded")
    @State private var isDownloadsPopoverFocused: Bool = false // For focusing TextField
    @State private var currentDownloadProcess: Process? = nil
    @State private var useFLAC: Bool = false
    


    let logger = Logger(subsystem: "com.yourapp.soundcloud", category: "ui")

    // Function to trigger directory picker
    func pickDirectory() {
        selectDirectory { url in
            if let url = url {
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "downloadDirectoryBookmark")
                    UserDefaults.standard.synchronize()
                    downloadDirectory = url
                } catch {
                    print("Failed to create bookmark for \(url): \(error)")
                }
            }
        }
    }
    func restoreDownloadDirectory() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "downloadDirectoryBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    let newBookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(newBookmarkData, forKey: "downloadDirectoryBookmark")
                }
                if url.startAccessingSecurityScopedResource() {
                    downloadDirectory = url
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    func stopDownload(for item: DownloadItem) {
        // Only stop if this is the current download
        if let process = currentDownloadProcess, downloads.contains(where: { $0.id == item.id && $0.status == .downloading }) {
            process.terminate()
            currentDownloadProcess = nil
            if let idx = downloads.firstIndex(where: { $0.id == item.id }) {
                downloads[idx].status = .failed
                debugMessages.append("Download manually stopped for \(item.fileName)")
            }
        }
    }

    var body: some View {
        // Use NavigationStack to host the toolbar correctly
        NavigationStack {
            VStack(spacing: 0) {
                // Conditional Tab Bar - Shown below the toolbar area
                if tabManager.tabs.count > 1 {
                    tabBar
                        .frame(height: 30) // Keep fixed height
                        .background(Color(NSColor.windowBackgroundColor))
                }

                // Main content area fills remaining space
                contentArea
            }
            .toolbar {
                // ---- Toolbar Items ----

                // Back Button (Navigation Placement)
                ToolbarItem(placement: .navigation) {
                    Button {
                        tabManager.selectedTab?.container.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Back")
                    // Use the @Published canGoBack from the container
                    .disabled(!(tabManager.selectedTab?.container.canGoBack != true))
                }
                
                // Forward Button
                ToolbarItem(placement: .navigation) {
                    Button {
                        tabManager.selectedTab?.container.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help("Forward")
                    .disabled(!(tabManager.selectedTab?.container.canGoForward != true))
                }


                // Spacer to push other items to the right
                ToolbarItem(placement: .automatic) { Spacer() }

                // Download Button
                ToolbarItem(placement: .automatic) {
                    Button {
                        autofillDownloadURLAndShowPopover()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(
                                downloads.last?.status == .completed
                                ? Color(red: 0, green: 0.9, blue : 0.1) // Green downloads icon when success
                                : .primary
                            )
                    }
                    .help("Download Track/Playlist/Album/User (Cmd+D)")
                    .keyboardShortcut("d", modifiers: [.command]) // Use Cmd+D standard
                    .popover(isPresented: $showDownloadsPopover) {
                        DownloadsPopover(
                            downloadURLString: $downloadURLString,
                            downloads: $downloads,
                            debugMessages: $debugMessages,
                            downloadDirectory: $downloadDirectory,
                            pickDirectory: pickDirectory,
                            startDownload: startDownload,
                            openDownloadsFolder: openDownloadsFolder,
                            isInitiallyFocused: $isDownloadsPopoverFocused,
                            currentDownloadProcess: $currentDownloadProcess,
                            stopDownloadForItem: stopDownload, // <-- NEW
                            useFLAC: $useFLAC
                        )

                        .frame(minWidth: 400) // No height!
                        .padding()
                        .onDisappear {
                            isDownloadsPopoverFocused = false // Reset focus trigger
                        }
                    }
                }

                // Debug Console Button
                ToolbarItem(placement: .automatic) {
                    Button {
                        showDebugPopover = true
                    } label: {
                        Image(systemName: "ladybug")
                            .foregroundColor(
                                downloads.last?.status == .failed
                                ? Color(red: 1.0, green: 0.35, blue: 0.0) // your red-orange
                                : .primary
                            )
                    }
                    .help("Show Debug Console (Cmd+L)")
                    .keyboardShortcut("l", modifiers: [.command]) // Use Cmd+L standard
                    .popover(isPresented: $showDebugPopover) {
                        DebugConsole(messages: debugMessages)
                            .frame(width: 420, height: 220)
                            .padding()
                    }
                }
            } // End Toolbar
        } // End NavigationStack
        .onAppear {
            restoreDownloadDirectory()
            setupWindowAndEvents()
        }
    } // End body

    // MARK: - UI Components

    // Tab bar that distributes tabs evenly.
    var tabBar: some View {
        GeometryReader { geo in
            let tabWidth = geo.size.width / CGFloat(tabManager.tabs.count)
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    TabBarItemView(
                        tab: tab,
                        isSelected: tabManager.selectedTab?.id == tab.id,
                        onSelect: { tabManager.selectedTab = tab },
                        onClose: { tabManager.closeTab(tab) }
                    )
                    .frame(width: tabWidth)
                }
            }
        }
        .frame(height: 30)
        .background(Color(NSColor.windowBackgroundColor))
    }


    var contentArea: some View {
        Group {
            if !tabManager.tabs.isEmpty {
                ZStack {
                    ForEach(tabManager.tabs) { tab in
                        // Pass the container's view model if PersistentWebView needs it
                        PersistentWebView(container: tab.container)
                            .opacity(tabManager.selectedTab?.id == tab.id ? 1 : 0)
                            .allowsHitTesting(tabManager.selectedTab?.id == tab.id)
                            // No need for onAppear here anymore for callbacks, set in TabManager
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure content fills space
            } else {
                Text("No tab selected")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Popover Toggles

        func toggleDownloadsPopover() {
            if showDownloadsPopover {
                showDownloadsPopover = false
            } else {
                autofillDownloadURLAndShowPopover()
            }
        }

        func toggleDebugPopover() {
            showDebugPopover.toggle()
        }

        // MARK: - Keyboard Shortcuts and Window Events

        func setupWindowAndEvents() {
            // Window setup
            if let window = NSApplication.shared.windows.first {
                window.setContentSize(NSSize(width: 1280, height: 720))
                window.minSize = NSSize(width: 400, height: 300)
            }
            // Cmd+W closes tab
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "w" {
                    if let selected = self.tabManager.selectedTab {
                        self.tabManager.closeTab(selected)
                    }
                    return nil
                }

                // Cmd+T: new tab
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "t" {
                    if self.tabManager.tabs.count < 10 {
                        self.tabManager.addTab(url: URL(string: "https://soundcloud.com")!)
                    }
                    return nil
                }
                // Cmd+R: reload tab
                if event.modifierFlags.contains(.command),
                    event.charactersIgnoringModifiers?.lowercased() == "r" {
                    tabManager.selectedTab?.container.reload()
                    return nil
                }

                // Cmd+L: toggle debug popover
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "l" {
                    self.showDebugPopover.toggle()
                    return nil
                }
                // Cmd+D: toggle downloads popover
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "d" {
                    if self.showDownloadsPopover {
                        self.showDownloadsPopover = false
                    } else {
                        self.autofillDownloadURLAndShowPopover()
                    }
                    return nil
                }
                
                return event // always return event for all other keys
            }

        }

        // MARK: - Download Popover Logic

        func autofillDownloadURLAndShowPopover() {
            if let container = tabManager.selectedTab?.container {
                container.webView.evaluateJavaScript("""
                (function() {
                    var url = window.location.href;
                    var path = window.location.pathname;

                    // Helper: is this a track page?
                    function isTrackPage(path) {
                        // /artistname/trackname (not /sets/, not /likes, not /reposts)
                        var parts = path.split('/').filter(Boolean);
                        return parts.length === 2 && parts[1] !== 'sets' && parts[1] !== 'likes' && parts[1] !== 'reposts';
                    }

                    // Helper: is this a playlist/album page?
                    function isPlaylistPage(path) {
                        // /artistname/sets/albumname
                        var parts = path.split('/').filter(Boolean);
                        return parts.length === 3 && parts[1] === 'sets';
                    }

                    // Helper: is this a user page?
                    function isUserPage(path) {
                        // /artistname only
                        var parts = path.split('/').filter(Boolean);
                        return parts.length === 1;
                    }

                    // 1. Track page
                    if (isTrackPage(path)) {
                        return url;
                    }
                    // 2. Playlist/album page
                    if (isPlaylistPage(path)) {
                        return url;
                    }
                    // 3. User page
                    if (isUserPage(path)) {
                        return url;
                    }
                    // 4. Fallback: canonical link
                    var canonical = document.querySelector('link[rel="canonical"]');
                    if (canonical && canonical.href) return canonical.href;

                    // 5. Fallback: first track/playlist link on page
                    var firstTrack = document.querySelector('a[href^="/"][href*="/"][href]:not([href*="/sets/"])');
                    if (firstTrack && firstTrack.href) return firstTrack.href;
                    var firstPlaylist = document.querySelector('a[href*="/sets/"]');
                    if (firstPlaylist && firstPlaylist.href) return firstPlaylist.href;

                    // 6. Default to window.location.href
                    return url;
                })()
                """) { (result, error) in
                    if let url = result as? String, !url.isEmpty {
                        self.downloadURLString = url
                    } else {
                        self.downloadURLString = ""
                    }
                    self.showDownloadsPopover = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isDownloadsPopoverFocused = true
                    }
                }
            } else {
                self.downloadURLString = ""
                self.showDownloadsPopover = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isDownloadsPopoverFocused = true
                }
            }
        }

    // MARK: - Download Logic
    func startDownload(_ urlString: String, to directory: URL, useFLAC: Bool) {

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            debugMessages.append("No valid URL to download.")
            return
        }
        
        // Writing command with arguments
        let scdlPath = "\(realUserHomeDirectory())/.local/bin/scdl"
        var arguments = ["-l", url.absoluteString, "--path", directory.path]
        if useFLAC {
                arguments.append("--flac")
            }
        arguments.append("-c")
        
        
        debugMessages.append("Running: \(scdlPath) \(arguments.joined(separator: " "))")
        if !FileManager.default.isExecutableFile(atPath: scdlPath) {
            debugMessages.append("ERROR: scdl not found at \(scdlPath).")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scdlPath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let ffmpegPaths = [ "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", env["PATH"] ?? "" ]
        env["PATH"] = ffmpegPaths.joined(separator: ":")
        process.environment = env
        
        // --- Place this block here ---
        let fileName = url.lastPathComponent // Simple filename guess
        let downloadItem = DownloadItem(url: url, status: .downloading, progress: 0, fileName: fileName, process: process)
        downloads.append(downloadItem)
        let downloadIndex = downloads.count - 1
        // ----------------------------

        self.currentDownloadProcess = process
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.currentDownloadProcess = nil
                // ... update download status ...
            }
        }
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            if let output = String(data: handle.availableData, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async { debugMessages.append(output) }
            }
        }

        process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    debugMessages.append("Download finished for \(url)")
                    if proc.terminationStatus == 0 {
                        // Force UI update with withAnimation
                        withAnimation {
                            downloads[downloadIndex].status = .completed
                        }
                    } else {
                        withAnimation {
                            downloads[downloadIndex].status = .failed
                        }
                        debugMessages.append("Download failed with status: \(proc.terminationStatus)")
                    }
                    // Explicitly trigger view update
                    self.currentDownloadProcess = nil
                }
            }

        do {
            try process.run()
            debugMessages.append("Started download for \(url)")
        } catch {
            debugMessages.append("Failed to start download: \(error.localizedDescription)")
            downloads[downloadIndex].status = .failed
        }
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadDirectory)
    }
    

} // End ContentView

// MARK: - Downloads Popover (Add FocusState)

struct DownloadsPopover: View {
    @Binding var downloadURLString: String
    @Binding var downloads: [DownloadItem]
    @Binding var debugMessages: [String]
    @Binding var downloadDirectory: URL
    var pickDirectory: () -> Void
    var startDownload: (String, URL, Bool) -> Void
    var openDownloadsFolder: () -> Void
    @Binding var isInitiallyFocused: Bool
    @Binding var currentDownloadProcess: Process?      // <-- Add this
    var stopDownloadForItem: (DownloadItem) -> Void
    @State private var showFailed = false

    @Binding var useFLAC: Bool
    @FocusState private var urlFieldIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download from SoundCloud")
                .font(.headline)
            TextField("Paste or edit SoundCloud URL", text: $downloadURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12, design: .monospaced))
                .focused($urlFieldIsFocused)
                .onSubmit {
                    if !downloadURLString.isEmpty {
                        startDownload(downloadURLString, downloadDirectory, useFLAC)
                    }
                }
                
            // New Toggle to choose FLAC format
            Toggle("Use FLAC if available", isOn: $useFLAC)
                .font(.system(size: 10))

            HStack {
                Text("Save to:").bold()
                Text(downloadDirectory.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(action: pickDirectory) {
                    Image(systemName: "folder")
                }
                .help("Choose download folder")
            }
            HStack {
                Button("Start Download") {
                    startDownload(downloadURLString, downloadDirectory, useFLAC)
                }
                .disabled(downloadURLString.isEmpty)

                Spacer()

                Button(action: openDownloadsFolder) {
                    Text("Show downloads in Finder")
                }
            }
            .padding(.top, 8)

            // Ongoing Downloads Section
            if downloads.contains(where: { $0.status == .downloading }) {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.filter { $0.status == .downloading }) { item in
                            DownloadRow(item: item, onStop: {
                                if let process = item.process {
                                    process.terminate()
                                    // Update status to failed
                                    if let idx = downloads.firstIndex(where: { $0.id == item.id }) {
                                        downloads[idx].status = .failed
                                        debugMessages.append("Download manually stopped for \(item.fileName)")
                                    }
                                }
                            })
                        }
                    }
                }
                .frame(minHeight: 40, maxHeight: 200) // min for 1 row, max for 5+
            }

            // Completed Downloads Section
            if downloads.contains(where: { $0.status == .completed }) {
                Divider()
                //Text("Completed Downloads").font(.subheadline)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.filter { $0.status == .completed }) { item in
                            DownloadRow(item: item)
                        }
                    }
                }
                .frame(minHeight: 20, maxHeight: 80) //
            }

            // Failed Downloads Section (with DisclosureGroup)
            if downloads.contains(where: { $0.status == .failed }) {
                DisclosureGroup(isExpanded: $showFailed) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(downloads.filter { $0.status == .failed }) { item in
                                DownloadRow(item: item)
                            }
                        }
                    }
                    .frame(minHeight: 20, maxHeight: 120) //
                } label: {
                    HStack {
                        Text("Failed Downloads (\(downloads.filter { $0.status == .failed }.count))")
                            .font(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showFailed.toggle() }
                }
                .onAppear {
                    if isInitiallyFocused {
                        urlFieldIsFocused = true
                    }
                }
            }
        }
        .frame(minWidth: 400) // min for 1 row, max for
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    var onStop: (() -> Void)? = nil

    // For ASCII animation: rotating through ["𓊝", "﹏𓊝", "﹏﹏𓊝", "﹏﹏𓊝﹏", "﹏﹏𓊝﹏𓂁", "﹏﹏﹏𓊝𓂁⊹", "﹏﹏𓊝⊹", "﹏𓊝"]
    @State private var asciiIndex: Int = 0
    private let asciiFrames = [
        "🦑———✧———",
        "—🦑——✧———",
        "——🦑—✧———",
        "———🦑✧———",
        "———🦑—✧——",
        "———🦑——✧—",
        "———🦑———✧",
        "———🦑——✧—",
        "———🦑—✧——",
        "———🦑✧———",
        "——🦑—✧———",
        "—🦑——✧———",
        "🦑———✧———",
        "🦐———✦———",
        "—🦐——✦———",
        "——🦐—✦———",
        "———🦐✦———",
        "———🦐—✦——",
        "———🦐——✦—",
        "———🦐———✦",
        "———🦐——✦—",
        "———🦐—✦——",
        "———🦐✦———",
        "——🦐—✦———",
        "—🦐——✦———",
        "🦐———✦———",
        "🦞———❂———",
        "—🦞——❂———",
        "——🦞—❂———",
        "———🦞❂———",
        "———🦞—❂——",
        "———🦞——❂—",
        "———🦞———❂",
        "———🦞——❂—",
        "———🦞—❂——",
        "———🦞❂———",
        "——🦞—❂———",
        "—🦞——❂———",
        "🦞———❂———"
    ]
    private let animationInterval = 0.1 // seconds

    var body: some View {
        HStack {
            Text(item.fileName)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Spacer()
            if item.status == .downloading {
                HStack(spacing: 8) {
                    // ASCII animation
                    Text(asciiFrames[asciiIndex])
                        .font(.system(size: 16, design: .monospaced))
                        .frame(width: 128, alignment: .trailing)
                        .accessibilityLabel("Downloading")
                        .onAppear {
                            // Start timer for ASCII animation
                            Timer.scheduledTimer(withTimeInterval: animationInterval, repeats: true) { timer in
                                asciiIndex = (asciiIndex + 1) % asciiFrames.count
                                // Stop timer if download is no longer active
                                if item.status != .downloading {
                                    timer.invalidate()
                                }
                            }
                        }
                    // Optionally, show percent if you want:
                    // Text("\(Int(item.progress * 100))%")
                    //     .font(.caption2)
                    //     .foregroundColor(.secondary)

                    // Native-style stop/cancel button
                    Button(action: { onStop?() }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 20, weight: .regular))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Stop this download")
                }
            } else if item.status == .completed {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 4)
    }
}





// MARK: - Debug Console

struct DebugConsole: View {
    let messages: [String]
    let redOrange = Color(red: 1.0, green: 0.35, blue: 0.0)
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(messages.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(redOrange)
                    .textSelection(.enabled)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id("consoleText")
                // Hidden anchor for scrolling
                Color.clear.frame(height: 1).id("bottom")
            }
            .background(Color.black)
            .cornerRadius(6)
            .defaultScrollAnchor(.bottom) // SwiftUI 5+ auto-scrolls unless user scrolls up[9]
            .onChange(of: messages.count) { _, _ in
                if messages.count > 0 {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
