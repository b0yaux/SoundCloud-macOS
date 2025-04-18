//
//  CustomWKWebView.swift
//  SoundCloud
//
//  Created by Jaufré on 11/02/2025.
//
import WebKit
import AppKit

enum ContextualMenuAction {
    case openNewTab
    case openNewWindow
}

class CustomWKWebView: WKWebView {
    /// Closure to be called when “Open Link in New Tab” is selected.
    var onOpenNewTab: ((URL) -> Void)?
    /// Closure to be called when “Open Link in New Window” is selected.
    var onOpenNewWindow: ((URL) -> Void)?
    
    /// Tracks which action was triggered (if needed in delegate methods).
    var contextualMenuAction: ContextualMenuAction?
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.items.removeAll { $0.identifier?.rawValue == "OpenLinkInNewTab" }
        menu.items.removeAll { $0.identifier?.rawValue == "OpenLinkInNewWindow" }
        
        let point = convert(event.locationInWindow, from: nil)
        let js = "document.elementFromPoint(\(point.x), \(point.y))?.closest('a')?.href;"
        
        evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self,
                  let urlStr = result as? String,
                  let url = URL(string: urlStr),
                  url.host?.contains("soundcloud.com") == true else { return }
            
            // Add "Open Link in New Tab" item
            let newTabItem = NSMenuItem(title: "Open Link in New Tab", action: #selector(self.openNewTabAction(_:)), keyEquivalent: "")
            newTabItem.identifier = NSUserInterfaceItemIdentifier("OpenLinkInNewTab")
            newTabItem.target = self
            newTabItem.representedObject = url  // Store the URL directly
            menu.insertItem(newTabItem, at: 0)
            
            // Similarly, add "Open Link in New Window" item if desired.
        }
    }


    @objc func openNewTabAction(_ sender: NSMenuItem) {
        // Use a direct URL cast because the represented object was set to a URL
        guard let url = sender.representedObject as? URL else {
            print("Error: representedObject is not a URL")
            return
        }
        DispatchQueue.main.async { // Ensure we're on the main thread
            self.onOpenNewTab?(url)
            print("Custom Menu Action: Open in New Tab requested for \(url)")
        }
    }


    @objc func openNewWindowAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        DispatchQueue.main.async {
            self.onOpenNewWindow?(url)
            print("Custom Menu Action: Open in New Window requested for \(url)")
        }
    }


}
