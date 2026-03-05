//
//  AppUpdater.swift
//  Tab Note
//

import Foundation
import AppKit
import Sparkle

private func presentUpdaterNotConfiguredAlert() {
    let alert = NSAlert()
    alert.messageText = "Auto-update Not Configured"
    alert.informativeText = "Sparkle needs a valid SUFeedURL and SUPublicEDKey in Info.plist."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open Website")
    alert.addButton(withTitle: "OK")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn,
       let url = URL(string: "https://kientran.ca") {
        NSWorkspace.shared.open(url)
    }
}

final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    private var updaterController: SPUStandardUpdaterController?

    private var feedURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var publicEDKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isAutoUpdateConfigured: Bool {
        updaterController != nil && !feedURL.isEmpty && !publicEDKey.isEmpty
    }

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard isAutoUpdateConfigured else {
            presentUpdaterNotConfiguredAlert()
            return
        }
        updaterController?.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard isAutoUpdateConfigured else { return }
        updaterController?.updater.checkForUpdatesInBackground()
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        print("[Updater] Appcast loaded - \(appcast.items.count) item(s)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[Updater] Update available: \(item.displayVersionString)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("[Updater] Already up to date.")
    }
}
