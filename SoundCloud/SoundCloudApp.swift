//
//  SoundCloudApp.swift
//  SoundCloud
//
//  Created by Romain on 2/6/25.
//  Edited by Jaufré on 2/11/25.
//

import SwiftUI

@main
struct SoundCloudApp: App {
    @StateObject var tabManager = TabManager()
    @AppStorage("appearance") private var appearance: String = "system" // "light", "dark", or "system"
    
    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tabManager)
                .preferredColorScheme(preferredColorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    tabManager.addTab(url: URL(string: "https://soundcloud.com")!)
                }
                .keyboardShortcut("t", modifiers: [.command])
                Button("Open Current Link in New Tab") {
                    if let url = tabManager.selectedTab?.container.currentURL {
                        tabManager.addTab(url: url)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        #if os(macOS)
        if #available(macOS 12.0, *) {
            Settings {
                PreferencesView()
            }
        }
        #endif
    }
}




struct PreferencesView: View {
    @AppStorage("appearance") private var appearance: String = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.headline)
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(RadioGroupPickerStyle())
            .frame(width: 200)
            Spacer()
        }
        .padding(24)
        .frame(width: 260, height: 140)
    }
}


