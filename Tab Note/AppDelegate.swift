//
//  AppDelegate.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import Cocoa
import SwiftUI
import SwiftData
import Combine
import Carbon.HIToolbox


// MARK: - Panel subclass that accepts key focus when clicked
class ActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var panel: NSPanel?
    var hotKeyRef: EventHotKeyRef?
    var localMonitor: Any?
    var statusItem: NSStatusItem?
    let notesStore = NotesStore()
    let settingsManager = SettingsManager.shared
    var modelContainer: ModelContainer?
    var settingsSub: AnyCancellable?
    private var hotKeyHandlerInstalled = false
    private var autoCheckMenuItem: NSMenuItem?
    private var updateStatusMenuItem: NSMenuItem?
    private var panelsByWindowID: [String: NSPanel] = [:]

    static var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Show both dock icon AND status bar (accessory policy shows neither by default)
        // We want the dock icon visible while app is running
        NSApp.setActivationPolicy(.regular)

        setupModelContainer()
        registerGlobalHotKey()
        setupLocalEventMonitor()
        setupStatusBar()
        setupPanel()

        // Auto-update check on launch
        if settingsManager.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                AppUpdater.shared.checkForUpdatesInBackground()
            }
        }
    }

    // MARK: - SwiftData + CloudKit

    func setupModelContainer() {
        let schema = Schema([TabNote.self, DeletedNote.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.kientran.TabNote")
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            notesStore.setup(context: ModelContext(container))
        } catch {
            print("⚠️ ModelContainer failed: \(error). Falling back to local.")
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                self.modelContainer = container
                notesStore.setup(context: ModelContext(container))
            }
        }
    }

    // MARK: - Status Bar Menu

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Tab Note")
        statusItem?.button?.toolTip = "Tab Note"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeMenuItem(title: "Show Tab Note", action: #selector(showPanel)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeMenuItem(title: "New Note", action: #selector(newNote)))
        menu.addItem(makeTextStyleSubmenuItem())
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeMenuItem(title: "Check for Updates", action: #selector(checkUpdates)))
        let autoCheck = makeMenuItem(title: "Auto-check on Launch", action: #selector(toggleAutoCheckUpdates))
        autoCheckMenuItem = autoCheck
        menu.addItem(autoCheck)

        let updateStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updateStatus.isEnabled = false
        updateStatusMenuItem = updateStatus
        menu.addItem(updateStatus)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        refreshStatusMenuState()
        statusItem?.menu = menu
    }

    @objc func showPanel() { positionAndShowPanel(windowID: NotesStore.mainWindowID) }
    @objc func newNote() { notesStore.createNote() }
    @objc func checkUpdates() { AppUpdater.shared.checkForUpdates() }
    @objc func toggleAutoCheckUpdates() {
        settingsManager.autoCheckUpdates.toggle()
        refreshStatusMenuState()
    }
    @objc func applyTextStyleFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .applyTextStyle, object: raw)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenuState()
    }

    private func refreshStatusMenuState() {
        autoCheckMenuItem?.state = settingsManager.autoCheckUpdates ? .on : .off
        if AppUpdater.shared.isAutoUpdateConfigured {
            updateStatusMenuItem?.title = "Auto-update: Configured"
        } else {
            updateStatusMenuItem?.title = "Auto-update: Not configured (Sparkle + feed URL required)"
        }
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makeTextStyleSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Text Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu(title: "Text Style")
        for style in TextStyleCommand.allCases {
            let item = NSMenuItem(title: style.menuTitle, action: #selector(applyTextStyleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            styleMenu.addItem(item)
        }
        parent.submenu = styleMenu
        return parent
    }

    // MARK: - Global Hotkey

    func registerGlobalHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x544E_4F54)
        hotKeyID.id = 1
        if !hotKeyHandlerInstalled {
            var eventType = EventTypeSpec()
            eventType.eventClass = OSType(kEventClassKeyboard)
            eventType.eventKind = UInt32(kEventHotKeyPressed)
            InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
                AppDelegate.shared?.togglePanel()
                return noErr
            }, 1, &eventType, nil, nil)
            hotKeyHandlerInstalled = true
        }
        let keyCode = UInt32(settingsManager.hotkeyKeyCode)
        let mods = UInt32(settingsManager.hotkeyModifiers)
        let status = RegisterEventHotKey(keyCode, mods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("⚠️ Failed to register hotkey (\(settingsManager.hotkeyDisplayLabel)) with status \(status)")
        } else {
            print("✅ Registered hotkey: \(settingsManager.hotkeyDisplayLabel)")
        }
    }

    // MARK: - Local Event Monitor

    func setupLocalEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let normalizedFlags = flags.subtracting([.numericPad, .function, .help, .capsLock])
            let windowID = self.currentWindowIDForKeyEvents()
            // Arrow keys inject .numericPad + .function — strip before comparing.
            let arrowFlags = flags.subtracting([.numericPad, .function, .help])

            if normalizedFlags == .command && event.keyCode == 17 { self.notesStore.createNote(in: windowID); return nil }
            if flags == .command && event.keyCode == 49 { self.notesStore.deleteSelectedNote(in: windowID); return nil }
            if normalizedFlags == [.command, .shift] && event.keyCode == 17 { self.notesStore.recoverLastDeletedNote(); return nil }
            if normalizedFlags == .command && event.keyCode == 37 {   // Cmd+L = rename
                self.notesStore.renamingNoteId = self.notesStore.selectedNoteId(in: windowID); return nil
            }
            if normalizedFlags == .command && event.keyCode == 3 {    // Cmd+F = search
                NotificationCenter.default.post(name: .toggleSearchBar, object: windowID); return nil
            }
            if self.isCommandShiftH(event: event, flags: normalizedFlags) {   // Cmd+Shift+H = toggle tab area visibility
                NotificationCenter.default.post(name: .toggleTabAreaVisibility, object: windowID); return nil
            }
            if self.isCommandShiftI(event: event, flags: normalizedFlags) {   // Cmd+Shift+I = toggle AI matrix panel
                NotificationCenter.default.post(name: .toggleAIPanel, object: windowID); return nil
            }

            if arrowFlags == [.command, .option, .shift] && event.keyCode == 123 {   // Cmd+Opt+Shift+Left
                self.notesStore.selectAdjacentTab(by: -1, in: windowID)
                return nil
            }
            if arrowFlags == [.command, .option, .shift] && event.keyCode == 124 {   // Cmd+Opt+Shift+Right
                self.notesStore.selectAdjacentTab(by: 1, in: windowID)
                return nil
            }

            // ⌘⌥← / ⌘⌥→  — move active tab left / right
            // Must use arrowFlags (stripped), not flags, because arrow keys set .numericPad + .function
            if arrowFlags == [.command, .option] && event.keyCode == 123 {   // ←
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    self.notesStore.moveSelectedTab(by: -1, in: windowID)
                }
                return nil
            }
            if arrowFlags == [.command, .option] && event.keyCode == 124 {   // →
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    self.notesStore.moveSelectedTab(by: 1, in: windowID)
                }
                return nil
            }

            let numKeyCodes: [UInt16: Int] = [18:0,19:1,20:2,21:3,23:4,22:5,26:6,28:7,25:8]
            if normalizedFlags == .command, let idx = numKeyCodes[event.keyCode] {
                self.notesStore.selectTab(at: idx, in: windowID); return nil
            }
            return event
        }
    }

    private func isCommandShiftI(event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.contains(.command), flags.contains(.shift) else { return false }
        if flags.contains(.control) || flags.contains(.option) { return false }
        if event.keyCode == 34 { return true } // Physical "I" key on ANSI layout.
        return event.charactersIgnoringModifiers?.lowercased() == "i"
    }

    private func isCommandShiftH(event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.contains(.command), flags.contains(.shift) else { return false }
        if flags.contains(.control) || flags.contains(.option) { return false }
        if event.keyCode == 4 { return true } // Physical "H" key on ANSI layout.
        return event.charactersIgnoringModifiers?.lowercased() == "h"
    }

    // MARK: - Panel

    func setupPanel() {
        let mainWindowID = NotesStore.mainWindowID
        let newPanel = makePanel(
            windowID: mainWindowID,
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            makeMovableByBackground: true
        )
        newPanel.setFrameOrigin(NSPoint(x: 120, y: 120))
        self.panel = newPanel
        panelsByWindowID[mainWindowID] = newPanel
        positionAndShowPanel(windowID: mainWindowID)
    }

    // NSWindowDelegate — enforce minimum size (borderless panels ignore minSize)
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(300, frameSize.width), height: max(240, frameSize.height))
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              let windowID = windowID(for: closedWindow) else { return }

        panelsByWindowID.removeValue(forKey: windowID)
        notesStore.removeTabBarFrame(for: windowID)

        if windowID == NotesStore.mainWindowID {
            panel = nil
            return
        }

        let noteIDs = notesStore.notes(in: windowID).map(\.id)
        for id in noteIDs {
            _ = notesStore.moveNoteToWindow(id: id, windowID: NotesStore.mainWindowID)
        }
    }

    func togglePanel() {
        guard let mainPanel = panelsByWindowID[NotesStore.mainWindowID] else {
            setupPanel()
            return
        }
        mainPanel.isVisible ? hidePanel() : positionAndShowPanel(windowID: NotesStore.mainWindowID)
    }

    func positionAndShowPanel(windowID: String) {
        guard let targetPanel = panelsByWindowID[windowID] else { return }
        if windowID == NotesStore.mainWindowID {
            switch settingsManager.positionModeEnum {
            case .cursor:
                let mouse = NSEvent.mouseLocation
                let sz = targetPanel.frame.size
                var origin = NSPoint(x: mouse.x - sz.width/2, y: mouse.y - sz.height/2)

                // Find the screen containing the mouse cursor
                let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
                if let screen = targetScreen {
                    let sf = screen.visibleFrame
                    origin.x = max(sf.minX, min(origin.x, sf.maxX - sz.width))
                    origin.y = max(sf.minY, min(origin.y, sf.maxY - sz.height))
                }
                targetPanel.setFrameOrigin(origin)
            case .topRight:
                if let screen = NSScreen.main {
                    let sf = screen.visibleFrame
                    let sz = targetPanel.frame.size
                    targetPanel.setFrameOrigin(NSPoint(x: sf.maxX - sz.width - 20, y: sf.maxY - sz.height - 20))
                }
            }
        }

        targetPanel.makeKeyAndOrderFront(nil)
        if windowID == NotesStore.mainWindowID {
            InlineAnswerPanelController.shared.setTemporarilyHiddenByApp(false)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        panelsByWindowID[NotesStore.mainWindowID]?.orderOut(nil)
        InlineAnswerPanelController.shared.setTemporarilyHiddenByApp(true)
    }

    func handleTabDragEnd(noteId: String, sourceWindowID: String, screenPoint: NSPoint) {
        if let targetWindowID = notesStore.windowIDForTabBar(at: screenPoint) {
            moveNote(noteId: noteId, toWindowID: targetWindowID)
            panelsByWindowID[targetWindowID]?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        detachNoteToNewWindow(noteId: noteId, fromWindowID: sourceWindowID, at: screenPoint)
    }

    func beginTabDrag(noteId: String, sourceWindowID: String, screenPoint: NSPoint) {
        notesStore.beginTabDrag(noteId: noteId, sourceWindowID: sourceWindowID, screenPoint: screenPoint)
    }

    func updateTabDrag(noteId: String, sourceWindowID: String, screenPoint: NSPoint) {
        if let drag = notesStore.activeTabDrag,
           drag.noteId == noteId,
           drag.sourceWindowID == sourceWindowID {
            notesStore.updateTabDrag(screenPoint: screenPoint)
        } else {
            notesStore.beginTabDrag(noteId: noteId, sourceWindowID: sourceWindowID, screenPoint: screenPoint)
        }
    }

    func finishTabDrag(noteId: String, sourceWindowID: String, screenPoint: NSPoint) {
        handleTabDragEnd(noteId: noteId, sourceWindowID: sourceWindowID, screenPoint: screenPoint)
        notesStore.endTabDrag()
    }

    func detachNoteToNewWindow(noteId: String, fromWindowID: String, at screenPoint: NSPoint) {
        let newWindowID = UUID().uuidString
        _ = notesStore.moveNoteToWindow(id: noteId, windowID: newWindowID)
        closeDetachedWindowIfEmpty(windowID: fromWindowID)

        let frame = NSRect(x: screenPoint.x - 240, y: screenPoint.y - 260, width: 480, height: 520)
        let detached = makePanel(windowID: newWindowID, contentRect: frame, makeMovableByBackground: true)
        detached.setFrame(frame, display: false)
        panelsByWindowID[newWindowID] = detached
        detached.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func moveNote(noteId: String, toWindowID targetWindowID: String) {
        guard let sourceWindowID = notesStore.moveNoteToWindow(id: noteId, windowID: targetWindowID) else { return }
        closeDetachedWindowIfEmpty(windowID: sourceWindowID)
    }

    private func closeDetachedWindowIfEmpty(windowID: String) {
        guard windowID != NotesStore.mainWindowID else { return }
        guard notesStore.notes(in: windowID).isEmpty else { return }
        guard let emptyPanel = panelsByWindowID[windowID] else { return }
        panelsByWindowID.removeValue(forKey: windowID)
        notesStore.removeTabBarFrame(for: windowID)
        emptyPanel.orderOut(nil)
        emptyPanel.close()
    }

    private func makePanel(windowID: String, contentRect: NSRect, makeMovableByBackground: Bool) -> ActivatingPanel {
        let contentView = ContentView(windowID: windowID)
            .environmentObject(notesStore)
            .environmentObject(settingsManager)

        let newPanel = ActivatingPanel(
            contentRect: contentRect,
            styleMask: [.resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.identifier = NSUserInterfaceItemIdentifier(windowID)
        newPanel.contentView = NSHostingView(rootView: contentView)
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isMovableByWindowBackground = makeMovableByBackground
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.minSize = NSSize(width: 300, height: 240)
        newPanel.contentView?.wantsLayer = true
        newPanel.contentView?.layer?.cornerRadius = 12
        newPanel.contentView?.layer?.masksToBounds = true
        newPanel.delegate = self
        return newPanel
    }

    private func currentWindowIDForKeyEvents() -> String {
        if let keyWindow = NSApp.keyWindow,
           let id = windowID(for: keyWindow) {
            return id
        }
        return NotesStore.mainWindowID
    }

    private func windowID(for window: NSWindow) -> String? {
        if let id = window.identifier?.rawValue {
            return id
        }
        return panelsByWindowID.first(where: { $0.value == window })?.key
    }
}
