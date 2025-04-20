//
//  TabManager.swift
//  SoundCloud
//
//  Created by Jaufré on 11/02/2025.
//

import Foundation
import SwiftUI
import WebKit

// Represents one tab in your app.
struct TabItem: Identifiable {
    let id = UUID()
    let url: URL
    let container: WebViewContainer

    // Custom initializer that creates the container automatically.
    init(url: URL) {
        self.url = url
        self.container = WebViewContainer(url: url)
    }
}

extension TabItem: Equatable {
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        return lhs.id == rhs.id
    }
}

extension TabItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Manages a list of tabs.
class TabManager: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedTab: TabItem?
    
    init() {
        let defaultURL = URL(string: "https://soundcloud.com")!
        let initialTab = TabItem(url: defaultURL)
        // Set up closures for the initial tab's container!
        initialTab.container.onOpenNewTab = { [weak self] url in
            DispatchQueue.main.async {
                print(">>> Request to open in NEW TAB: \(url)")
                self?.addTab(url: url)
            }
        }
        initialTab.container.onOpenNewWindow = { [weak self] url in
            DispatchQueue.main.async {
                guard let self = self else { return }
                print(">>> Request to open in NEW WINDOW: \(url)")
                _ = createNewWindow(for: url)
            }
        }

        tabs.append(initialTab)
        selectedTab = initialTab
    }

    
    func addTab(url: URL) {
        DispatchQueue.main.async {
            guard self.tabs.count < 10 else {
                NSSound.beep()
                return
            }
            
            let newTab = TabItem(url: url)
            
            // Set closure for new tab actions:
            newTab.container.onOpenNewTab = { [weak self] url in
                DispatchQueue.main.async {
                    print(">>> Request to open in NEW TAB: \(url)")
                    self?.addTab(url: url)
                }
            }
            newTab.container.onOpenNewWindow = { url in
                DispatchQueue.main.async {
                    print(">>> Request to open in NEW WINDOW: \(url)")
                    _ = createNewWindow(for: url)
                }
            }
            
            self.tabs.append(newTab)
            self.selectedTab = newTab
            print("--- Tab added: \(url). Total tabs: \(self.tabs.count)")
        }
    }



    
    func closeTab(_ tab: TabItem) {
        // Remove the tab from the array.
        tabs.removeAll { $0.id == tab.id }
        // If the closed tab was the selected one,
        // set the selected tab to the last tab in the list.
        if selectedTab?.id == tab.id {
            selectedTab = tabs.last
        }
        // If there are no tabs left, quit the app.
        if tabs.isEmpty {
            NSApp.terminate(nil)
        }
    }

}

extension URL {
    var shortDisplayName: String {
        if self.absoluteString == "https://soundcloud.com" {
            return "Home"
        }
        let comps = self.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if comps.isEmpty {
            return "Home"
        }
        return comps.last!.capitalized
    }
}

