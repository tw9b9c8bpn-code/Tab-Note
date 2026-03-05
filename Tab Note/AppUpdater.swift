//
//  AppUpdater.swift
//  Tab Note
//
//  Auto-update via Sparkle 2.
//
//  SETUP REQUIRED (one-time in Xcode):
//  1. File → Add Package Dependencies…
//     URL: https://github.com/sparkle-project/Sparkle
//     Version: Up to Next Major → 2.0.0
//     Add "Sparkle" library to the "Tab Note" target.
//  2. Add SUFeedURL to Info.plist:
//     Key:   SUFeedURL
//     Value: https://YOUR-SERVER.com/appcast.xml
//  3. Generate an EdDSA key pair:
//     ./bin/generate_keys    (run from Sparkle's Tools folder)
//     → Paste the PUBLIC key into Info.plist as SUPublicEDKey.
//  4. Host an appcast.xml (see template at bottom of this file).
//  5. Sign your .zip with:
//     ./bin/sign_update TabNote.zip   (outputs the sparkle:edSignature value)

import Foundation
import AppKit

private func presentUpdaterNotConfiguredAlert() {
    let alert = NSAlert()
    alert.messageText = "Auto-update Not Configured"
    alert.informativeText = "Sparkle is not fully configured yet. Add Sparkle + SUFeedURL to enable in-app updates."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open Website")
    alert.addButton(withTitle: "OK")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn,
       let url = URL(string: "https://kientran.ca") {
        NSWorkspace.shared.open(url)
    }
}

#if canImport(Sparkle)
import Sparkle

/// Thin singleton wrapper around SPUStandardUpdaterController.
/// Works automatically once Sparkle is added via SPM.
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    private var updaterController: SPUStandardUpdaterController?
    private var isFeedConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }
        return !feed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAutoUpdateConfigured: Bool {
        updaterController != nil && isFeedConfigured
    }

    private override init() {
        super.init()
        // Initialise on the main thread before any UI appears
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Trigger an immediate (user-initiated) update check — e.g. from Settings button.
    func checkForUpdates() {
        guard isAutoUpdateConfigured else {
            presentUpdaterNotConfiguredAlert()
            return
        }
        updaterController?.checkForUpdates(nil)
    }

    /// Called at launch when autoCheckUpdates == true.
    func checkForUpdatesInBackground() {
        guard isAutoUpdateConfigured else { return }
        updaterController?.updater.checkForUpdatesInBackground()
    }

    // MARK: - SPUUpdaterDelegate (optional hooks)

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        print("[Updater] Appcast loaded – \(appcast.items.count) item(s)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[Updater] Update available: \(item.displayVersionString)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("[Updater] Already up to date.")
    }
}

#else

// ────────────────────────────────────────────────────────────────────────────
// STUB — keeps the project building before Sparkle SPM package is added.
// Delete this block (or the whole #else branch) once Sparkle is installed.
// ────────────────────────────────────────────────────────────────────────────
final class AppUpdater {
    static let shared = AppUpdater()
    private init() {}
    var isAutoUpdateConfigured: Bool { false }

    func checkForUpdates() {
        presentUpdaterNotConfiguredAlert()
    }

    func checkForUpdatesInBackground() {}
}
#endif


// ────────────────────────────────────────────────────────────────────────────
// APPCAST TEMPLATE  (host this at your SUFeedURL)
// ────────────────────────────────────────────────────────────────────────────
//
// <?xml version="1.0" encoding="utf-8"?>
// <rss version="2.0"
//      xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
//   <channel>
//     <title>Tab Note</title>
//     <link>https://YOUR-SERVER.com/appcast.xml</link>
//     <item>
//       <title>Version 1.1</title>
//       <sparkle:version>11</sparkle:version>              <!-- CFBundleVersion -->
//       <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
//       <pubDate>Tue, 04 Mar 2026 06:00:00 +0000</pubDate>
//       <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
//       <enclosure
//         url="https://YOUR-SERVER.com/releases/TabNote-1.1.zip"
//         length="1234567"
//         type="application/octet-stream"
//         sparkle:edSignature="BASE64_ED_SIGNATURE_HERE"/>
//     </item>
//   </channel>
// </rss>
