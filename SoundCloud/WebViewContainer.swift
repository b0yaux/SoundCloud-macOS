import Foundation
import SwiftUI
import WebKit
import Combine // <-- Import Combine

class WebViewContainer: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var webView: CustomWKWebView
    @Published var currentURL: URL?
    @Published var currentTitle: String?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    
    var onOpenNewTab: ((URL) -> Void)?
    var onOpenNewWindow: ((URL) -> Void)?

    private var coordinator: Coordinator!
    private var cancellables = Set<AnyCancellable>() // <-- For Combine observers

    // --- Add Navigation Methods ---
    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }
    // --- End Navigation Methods ---

    
    init(url: URL) {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Basic JS to monitor URL and Title changes (could be more robust)
        let js = """
        (function() {
            var currentHref = '';
            var currentTitle = '';
            function checkChanges() {
                if (window.location.href !== currentHref || document.title !== currentTitle) {
                    currentHref = window.location.href;
                    currentTitle = document.title;
                    window.webkit.messageHandlers.urlChanged.postMessage({url: currentHref, title: currentTitle});
                }
                setTimeout(checkChanges, 500); // Check periodically
            }
            checkChanges();
        })();
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        config.userContentController = contentController
        config.websiteDataStore = WKWebsiteDataStore.default()

        self.webView = CustomWKWebView(frame: .zero, configuration: config)
        self.currentURL = url
        self.currentTitle = nil // Initial title is unknown

        super.init() // Call super.init() after initializing stored properties

        contentController.add(self, name: "urlChanged") // Add message handler

        self.coordinator = Coordinator(self)
        self.webView.navigationDelegate = self.coordinator // Use Coordinator
        self.webView.uiDelegate = self.coordinator       // Use Coordinator

        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canGoBack, on: self)
            .store(in: &cancellables)
        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canGoForward, on: self)
            .store(in: &cancellables)

        
        // Pass through callbacks from CustomWKWebView
        self.webView.onOpenNewTab = { [weak self] url in
            self?.onOpenNewTab?(url)
        }
        self.webView.onOpenNewWindow = { [weak self] url in
            self?.onOpenNewWindow?(url)
        }

        // Load the initial URL
        let request = URLRequest(url: url)
        self.webView.load(request)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.canGoBack = self.webView.canGoBack
            self.canGoForward = self.webView.canGoForward
        }
    }


    // Handle messages from JavaScript
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "urlChanged",
           let dict = message.body as? [String: Any],
           let newURLString = dict["url"] as? String,
           let newTitle = dict["title"] as? String,
           let newURL = URL(string: newURLString) {

            DispatchQueue.main.async {
                 // Only update if changed to avoid potential loops/redundancy
                if self.currentURL != newURL {
                    self.currentURL = newURL
                }
                if self.currentTitle != newTitle {
                   self.currentTitle = newTitle
                }
            }
        }
    }

    // MARK: - Coordinator (Ensure delegate methods update state correctly if needed)
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        // --- Existing Delegate Methods ---

        // (Ensure didFinish updates title/URL if JS method fails)
         func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Navigation finished. canGoBack: \(webView.canGoBack), canGoForward: \(webView.canGoForward)")
             // Update URL and Title from the webView as a fallback
             if let newURL = webView.url {
                DispatchQueue.main.async {
                    if self.parent.currentURL != newURL {
                         self.parent.currentURL = newURL
                    }
                     let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                     if !title.isEmpty && self.parent.currentTitle != title {
                         self.parent.currentTitle = title
                     }
                 }
            }
            // Note: canGoBack/canGoForward are handled by Combine KVO publishers now.
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Navigation error: \(error.localizedDescription)")
            // Handle error appropriately (e.g., show an alert)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Provisional navigation error: \(error.localizedDescription)")
            // Handle error appropriately
        }

        // Handle requests to open new windows/tabs
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            DispatchQueue.main.async {
                self.parent.onOpenNewTab?(url) // Directly trigger new tab
            }
            return nil
        }
    }
}
