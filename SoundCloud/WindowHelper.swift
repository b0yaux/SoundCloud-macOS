//
//  WindowHelper.swift
//  SoundCloud
//
//  Created by Jaufré on 11/02/2025.
//

import Foundation
import SwiftUI
import AppKit

func createNewWindow(for url: URL) -> NSWindow {
    let webContainer = WebViewContainer(url: url)
    webContainer.onOpenNewTab = { newURL in
        // Optionally, open in new tab of new window, or use TabManager logic
        print("New tab requested for \(newURL)")
    }
    webContainer.onOpenNewWindow = { newURL in
        print("New window requested for \(newURL)")
    }
    let hostingController = NSHostingController(rootView: PersistentWebView(container: webContainer))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "SoundCloud - \(url.host ?? url.absoluteString)"
    window.setContentSize(NSSize(width: 1280, height: 720))
    window.minSize = NSSize(width: 400, height: 300)
    window.makeKeyAndOrderFront(nil)
    return window
}
