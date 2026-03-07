//
//  Tab_NoteApp.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import SwiftUI
import SwiftData

@main
struct Tab_NoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppDelegate.shared?.showFloatingSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
