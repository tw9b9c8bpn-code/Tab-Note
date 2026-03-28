//
//  ContentView.swift
//  Tab Note
//

import SwiftUI
import AppKit

// Shared AI result model (used by FootnoteBarView + ContentView)
struct AIResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let content: String
}

enum SplitDirection {
    case vertical   // side by side (left | right)
    case horizontal // top / bottom
}

private enum SplitPaneKind {
    case primary
    case secondary
}

private struct SplitPaneState: Equatable {
    var noteIds: [String]
    var selectedNoteId: String
}

struct ContentView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager

    let windowID: String
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchRequestID = 0
    @State private var isTabAreaHidden = false
    @State private var primarySplitPane: SplitPaneState? = nil
    @State private var secondarySplitPane: SplitPaneState? = nil
    @State private var splitDirection: SplitDirection = .vertical
    @State private var activeSplitPane: SplitPaneKind = .primary
    @FocusState private var isSearchFieldFocused: Bool

    init(windowID: String = NotesStore.mainWindowID) {
        self.windowID = windowID
    }

    private var themeColor: Color {
        let hex = settings.appThemeHex
        if let theme = ThemeColor(rawValue: hex) {
            return Color(hex: theme.hex(isDark: settings.isDarkMode)) ?? defaultBackground
        }
        return defaultBackground
    }

    private var defaultBackground: Color {
        settings.isDarkMode ? Color(white: 0.13) : Color(white: 0.97)
    }

    private func setNoteColor(_ hex: String) {
        store.setNoteColor(id: store.selectedNoteId(in: windowID) ?? "", colorHex: hex)
    }

    private var selectedNoteID: String? {
        store.selectedNoteId(in: windowID)
    }

    private var selectedNote: TabNote? {
        store.selectedNote(in: windowID)
    }

    private var splitPanes: (primary: SplitPaneState, secondary: SplitPaneState)? {
        guard let primary = primarySplitPane,
              let secondary = secondarySplitPane,
              !primary.noteIds.isEmpty,
              !secondary.noteIds.isEmpty else {
            return nil
        }
        return (primary, secondary)
    }

    private var isSplitMode: Bool {
        splitPanes != nil
    }

    private var editorBinding: Binding<String> {
        Binding(
            get: { selectedNote?.content ?? "" },
            set: { newValue in
                guard let id = selectedNoteID else { return }
                store.updateNoteContent(id: id, content: newValue)
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main layout
            VStack(spacing: 0) {
                if !isTabAreaHidden && !isSplitMode {
                    TabBarView(windowID: windowID)
                    Divider().opacity(settings.isDarkMode ? 0.3 : 0.5)
                }

                // Search bar (appears on demand)
                if showSearch {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Search…", text: $searchQuery)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                            .focused($isSearchFieldFocused)
                            .onSubmit { searchRequestID += 1 }
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: { setSearchVisible(false) }) {
                            Text("Done")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(settings.isDarkMode ? Color(white: 0.17) : Color(white: 0.94))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Editor area — single or split
                if let splitPanes {
                    if splitDirection == .vertical {
                        HStack(spacing: 0) {
                            splitPaneView(splitPanes.primary, kind: .primary, showsCloseButton: false)
                            Divider()
                            splitPaneView(splitPanes.secondary, kind: .secondary, showsCloseButton: true)
                        }
                    } else {
                        VStack(spacing: 0) {
                            splitPaneView(splitPanes.primary, kind: .primary, showsCloseButton: false)
                            Divider()
                            splitPaneView(splitPanes.secondary, kind: .secondary, showsCloseButton: true)
                        }
                    }
                } else {
                    primaryEditor
                }

                Divider().opacity(settings.isDarkMode ? 0.3 : 0.5)

                FootnoteBarView(windowID: windowID)
            }
            .background(RightClickCatcherView(onThemeSelected: { hex in setNoteColor(hex) }))

            if let drag = store.activeTabDrag,
               drag.sourceWindowID == windowID,
               drag.targetWindowID == nil {
                Text("Release to create a new window")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settings.isDarkMode ? .white.opacity(0.92) : .black.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(settings.isDarkMode ? Color.black.opacity(0.38) : Color.white.opacity(0.88))
                    )
                    .padding(.bottom, 56)
                    .padding(.leading, 10)
                    .transition(.opacity)
                    .zIndex(110)
            }
        }
        .background(themeColor)
        .preferredColorScheme(settings.isDarkMode ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSearchBar)) { note in
            if let targetWindowID = note.object as? String, targetWindowID != windowID { return }
            toggleSearchBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTabAreaVisibility)) { note in
            if let targetWindowID = note.object as? String, targetWindowID != windowID { return }
            toggleTabAreaVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitViewRequested)) { note in
            guard let info = note.userInfo,
                  let noteId = info["noteId"] as? String,
                  let dirStr = info["direction"] as? String,
                  let winId = info["windowID"] as? String,
                  winId == windowID else { return }
            let dir: SplitDirection = dirStr == "horizontal" ? .horizontal : .vertical
            if isSplitMode,
               (primarySplitPane?.noteIds.contains(noteId) == true || secondarySplitPane?.noteIds.contains(noteId) == true),
               splitDirection == dir {
                closeSplit(selecting: selectedNoteID)
            } else {
                openSplit(targetNoteId: noteId, direction: dir)
            }
        }
        .onChange(of: selectedNoteID) { _, newValue in
            syncSplitSelection(with: newValue)
        }
        .onReceive(store.$notes) { _ in
            reconcileSplitState()
        }
    }

    // MARK: - Editor subviews

    @ViewBuilder
    private var primaryEditor: some View {
        let activeNoteID = selectedNoteID
        NoteEditorView(
            text: editorBinding,
            searchQuery: $searchQuery,
            windowID: windowID,
            noteId: activeNoteID,
            searchRequestID: searchRequestID,
            settings: settings,
            onThemeSelected: { hex in setNoteColor(hex) },
            onRTFChange: { rtf in
                if let id = activeNoteID {
                    store.updateNoteRTF(id: id, rtfData: rtf)
                }
            },
            initialRTF: selectedNote?.rtfData
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func splitPaneView(
        _ pane: SplitPaneState,
        kind: SplitPaneKind,
        showsCloseButton: Bool
    ) -> some View {
        VStack(spacing: 0) {
            SplitPaneTabBar(
                notes: pane.noteIds.compactMap { note(for: $0) },
                selectedNoteId: pane.selectedNoteId,
                isDarkMode: settings.isDarkMode,
                appThemeHex: settings.appThemeHex,
                windowID: windowID,
                showsCloseSplitButton: showsCloseButton,
                onSelectNote: { noteId in
                    selectPaneNote(noteId, in: kind)
                },
                onAddNote: {
                    addNote(to: kind)
                },
                onCloseSplit: {
                    closeSplit(selecting: pane.selectedNoteId)
                }
            )
            Divider().opacity(settings.isDarkMode ? 0.22 : 0.34)
            noteEditorView(
                noteId: pane.selectedNoteId,
                searchQuery: activeSplitPane == kind ? $searchQuery : .constant(""),
                searchRequestID: activeSplitPane == kind ? searchRequestID : 0,
                onBecameActive: {
                    activateSplitPane(kind)
                }
            )
            .id("\(kind)-\(pane.selectedNoteId)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSearchBar() {
        setSearchVisible(!showSearch)
    }

    private func setSearchVisible(_ visible: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            showSearch = visible
            if !visible {
                searchQuery = ""
            }
        }
        if visible {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private func toggleTabAreaVisibility() {
        withAnimation(.easeOut(duration: 0.15)) {
            isTabAreaHidden.toggle()
        }
    }

    private func note(for noteId: String?) -> TabNote? {
        guard let noteId else { return nil }
        return store.notes.first(where: { $0.id == noteId && $0.windowID == windowID })
    }

    @ViewBuilder
    private func noteEditorView(
        noteId: String?,
        searchQuery: Binding<String>,
        searchRequestID: Int,
        onBecameActive: (() -> Void)? = nil
    ) -> some View {
        let note = note(for: noteId)
        NoteEditorView(
            text: Binding(
                get: { note?.content ?? "" },
                set: { newValue in
                    guard let noteId else { return }
                    store.updateNoteContent(id: noteId, content: newValue)
                }
            ),
            searchQuery: searchQuery,
            windowID: windowID,
            noteId: noteId,
            searchRequestID: searchRequestID,
            settings: settings,
            onThemeSelected: { hex in setNoteColor(hex) },
            onRTFChange: { rtf in
                guard let noteId else { return }
                store.updateNoteRTF(id: noteId, rtfData: rtf)
            },
            onBecameActive: onBecameActive,
            initialRTF: note?.rtfData
        )
    }

    private func openSplit(targetNoteId: String, direction: SplitDirection) {
        let orderedIds = store.visualOrderedNoteIds(in: windowID)
        guard orderedIds.count > 1,
              let targetIndex = orderedIds.firstIndex(of: targetNoteId) else {
            NSSound.beep()
            return
        }

        let primaryIds: [String]
        let secondaryIds: [String]
        if targetIndex == 0 {
            primaryIds = Array(orderedIds.dropFirst())
            secondaryIds = [targetNoteId]
        } else {
            primaryIds = Array(orderedIds[..<targetIndex])
            secondaryIds = Array(orderedIds[targetIndex...])
        }

        guard !primaryIds.isEmpty, !secondaryIds.isEmpty else {
            NSSound.beep()
            return
        }

        primarySplitPane = SplitPaneState(
            noteIds: primaryIds,
            selectedNoteId: primaryIds.last ?? primaryIds[0]
        )
        secondarySplitPane = SplitPaneState(
            noteIds: secondaryIds,
            selectedNoteId: targetNoteId
        )
        splitDirection = direction
        activeSplitPane = .secondary
        store.setSelectedNoteId(targetNoteId, in: windowID)
    }

    private func closeSplit(selecting noteId: String?) {
        primarySplitPane = nil
        secondarySplitPane = nil
        if let noteId, selectedNoteID != noteId {
            store.setSelectedNoteId(noteId, in: windowID)
        }
    }

    private func syncSplitSelection(with newSelection: String?) {
        guard splitPanes != nil,
              let newSelection,
              note(for: newSelection) != nil else {
            return
        }

        if primarySplitPane?.noteIds.contains(newSelection) == true {
            primarySplitPane?.selectedNoteId = newSelection
            activeSplitPane = .primary
            return
        }

        if secondarySplitPane?.noteIds.contains(newSelection) == true {
            secondarySplitPane?.selectedNoteId = newSelection
            activeSplitPane = .secondary
            return
        }

        reconcileSplitState()
    }

    private func selectPaneNote(_ noteId: String, in kind: SplitPaneKind) {
        switch kind {
        case .primary:
            primarySplitPane?.selectedNoteId = noteId
        case .secondary:
            secondarySplitPane?.selectedNoteId = noteId
        }
        activeSplitPane = kind
        if selectedNoteID != noteId {
            store.setSelectedNoteId(noteId, in: windowID)
        }
    }

    private func activateSplitPane(_ kind: SplitPaneKind) {
        switch kind {
        case .primary:
            if let noteId = primarySplitPane?.selectedNoteId {
                selectPaneNote(noteId, in: .primary)
            }
        case .secondary:
            if let noteId = secondarySplitPane?.selectedNoteId {
                selectPaneNote(noteId, in: .secondary)
            }
        }
    }

    private func addNote(to kind: SplitPaneKind) {
        guard let noteId = store.createNote(in: windowID) else { return }
        switch kind {
        case .primary:
            primarySplitPane?.noteIds.append(noteId)
            primarySplitPane?.selectedNoteId = noteId
        case .secondary:
            secondarySplitPane?.noteIds.append(noteId)
            secondarySplitPane?.selectedNoteId = noteId
        }
        activeSplitPane = kind
    }

    private func reconcileSplitState() {
        guard var primary = primarySplitPane,
              var secondary = secondarySplitPane else {
            return
        }

        let orderedIds = store.visualOrderedNoteIds(in: windowID)
        let currentIdSet = Set(orderedIds)

        var primarySet = Set(primary.noteIds.filter { currentIdSet.contains($0) })
        var secondarySet = Set(secondary.noteIds.filter { currentIdSet.contains($0) })
        secondarySet.subtract(primarySet)

        let assignedIds = primarySet.union(secondarySet)
        let unassignedIds = orderedIds.filter { !assignedIds.contains($0) }
        if !unassignedIds.isEmpty {
            switch activeSplitPane {
            case .primary:
                primarySet.formUnion(unassignedIds)
            case .secondary:
                secondarySet.formUnion(unassignedIds)
            }
        }

        let primaryIds = orderedIds.filter { primarySet.contains($0) }
        let secondaryIds = orderedIds.filter { secondarySet.contains($0) }

        guard !primaryIds.isEmpty, !secondaryIds.isEmpty else {
            let fallbackSelection = note(for: selectedNoteID) != nil ? selectedNoteID : orderedIds.first
            closeSplit(selecting: fallbackSelection)
            return
        }

        primary.noteIds = primaryIds
        secondary.noteIds = secondaryIds

        if !primaryIds.contains(primary.selectedNoteId) {
            primary.selectedNoteId = primaryIds.last ?? primaryIds[0]
        }
        if !secondaryIds.contains(secondary.selectedNoteId) {
            secondary.selectedNoteId = secondaryIds.first ?? secondaryIds[0]
        }

        primarySplitPane = primary
        secondarySplitPane = secondary

        let activeSelection = activeSplitPane == .primary
            ? primary.selectedNoteId
            : secondary.selectedNoteId
        if selectedNoteID != activeSelection {
            store.setSelectedNoteId(activeSelection, in: windowID)
        }
    }
}

private func splitTabAccentColor(for appThemeHex: String) -> Color {
    switch appThemeHex {
    case ThemeColor.paleYellow.rawValue: return Color(hex: "ffe500") ?? .orange
    case ThemeColor.paleGreen.rawValue:  return Color(hex: "4A8C5C") ?? .orange
    case ThemeColor.palePink.rawValue:   return Color(hex: "C47285") ?? .orange
    case ThemeColor.paleBlue.rawValue:   return Color(hex: "4A7FA8") ?? .orange
    case ThemeColor.paleGray.rawValue:   return Color(hex: "8A8A8A") ?? .orange
    case ThemeColor.palePurple.rawValue: return Color(hex: "8A5FAA") ?? .orange
    default:                             return Color(hex: "BA775B") ?? .orange
    }
}

private struct SplitPaneTabBar: View {
    let notes: [TabNote]
    let selectedNoteId: String
    let isDarkMode: Bool
    let appThemeHex: String
    let windowID: String
    let showsCloseSplitButton: Bool
    let onSelectNote: (String) -> Void
    let onAddNote: () -> Void
    let onCloseSplit: () -> Void

    private var backgroundColor: Color {
        isDarkMode ? Color(white: 0.15) : Color(white: 0.95)
    }

    private var inactiveTabFill: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var inactiveTextColor: Color {
        isDarkMode ? .white.opacity(0.72) : .black.opacity(0.62)
    }

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(notes) { note in
                        SplitPaneTabItem(
                            note: note,
                            isActive: note.id == selectedNoteId,
                            windowID: windowID,
                            isDarkMode: isDarkMode,
                            appThemeHex: appThemeHex,
                            inactiveTabFill: inactiveTabFill,
                            inactiveTextColor: inactiveTextColor,
                            onSelect: {
                                onSelectNote(note.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Button(action: onAddNote) {
                Text("+")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(inactiveTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            if showsCloseSplitButton {
                Button(action: onCloseSplit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(inactiveTextColor.opacity(0.78))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(backgroundColor)
    }

    private func textColor(isActive: Bool) -> Color {
        if isActive {
            return appThemeHex == ThemeColor.paleYellow.rawValue
                ? Color(white: 0.12)
                : .white
        }
        return inactiveTextColor
    }
}

private struct SplitPaneTabItem: View {
    @EnvironmentObject var store: NotesStore

    let note: TabNote
    let isActive: Bool
    let windowID: String
    let isDarkMode: Bool
    let appThemeHex: String
    let inactiveTabFill: Color
    let inactiveTextColor: Color
    let onSelect: () -> Void

    @State private var showRenamePopover = false
    @State private var renameText = ""

    private var tabFill: Color {
        isActive ? splitTabAccentColor(for: appThemeHex) : inactiveTabFill
    }

    private var textColor: Color {
        if isActive {
            return appThemeHex == ThemeColor.paleYellow.rawValue
                ? Color(white: 0.12)
                : .white
        }
        return inactiveTextColor
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7))
                }
                Text(note.title)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: isActive ? .semibold : .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tabFill)
            )
        }
        .buttonStyle(.plain)
        .onChange(of: store.renamingNoteId) { _, id in
            if id == note.id {
                renameText = note.title
                showRenamePopover = true
                store.renamingNoteId = nil
            }
        }
        .popover(isPresented: $showRenamePopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                Text("Rename Note").font(.system(size: 12, weight: .semibold))
                TextField("Name", text: $renameText, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 160)
                HStack {
                    Button("Cancel") { showRenamePopover = false }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Rename", action: commitRename)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(width: 200)
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin Tab" : "Pin Tab") {
                store.togglePin(id: note.id)
            }
            Divider()
            Button("Rename") {
                renameText = note.title
                showRenamePopover = true
            }
            Button("Open in New Window") {
                openInNewWindow()
            }
            Divider()
            Button {
                NotificationCenter.default.post(
                    name: .splitViewRequested,
                    object: nil,
                    userInfo: ["noteId": note.id, "direction": "vertical", "windowID": windowID]
                )
            } label: {
                Label("Split Vertically", systemImage: "rectangle.split.2x1")
            }
            Button {
                NotificationCenter.default.post(
                    name: .splitViewRequested,
                    object: nil,
                    userInfo: ["noteId": note.id, "direction": "horizontal", "windowID": windowID]
                )
            } label: {
                Label("Split Horizontally", systemImage: "rectangle.split.1x2")
            }
            Divider()
            Menu("Theme") {
                Button("Default Orange") { store.setNoteColor(id: note.id, colorHex: "defaultOrange") }
                Divider()
                ForEach(ThemeColor.allCases, id: \.self) { color in
                    Button(color.displayName) { store.setNoteColor(id: note.id, colorHex: color.rawValue) }
                }
            }
            Menu("Export") {
                Button("Export as .txt") { store.exportNote(id: note.id, asTxt: true) }
                Button("Export as .md")  { store.exportNote(id: note.id, asTxt: false) }
            }
            Divider()
            Button("Delete", role: .destructive) { store.deleteNote(id: note.id) }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameNote(id: note.id, title: trimmed)
        }
        showRenamePopover = false
        store.renamingNoteId = nil
    }

    private func openInNewWindow() {
        let screenPoint = NSEvent.mouseLocation
        AppDelegate.shared?.detachNoteToNewWindow(
            noteId: note.id,
            fromWindowID: windowID,
            at: screenPoint
        )
    }
}

// MARK: - RightClickCatcherView

struct RightClickCatcherView: NSViewRepresentable {
    var onThemeSelected: (String) -> Void

    func makeNSView(context: Context) -> RightClickCatcherNSView {
        let view = RightClickCatcherNSView()
        view.onThemeSelected = onThemeSelected
        return view
    }

    func updateNSView(_ nsView: RightClickCatcherNSView, context: Context) {}
}

class RightClickCatcherNSView: NSView {
    var onThemeSelected: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "")
        menu.addItem(ThemeMenuHelper.createThemeMenuItem(target: self, action: #selector(themeBtnClicked(_:))))
        return menu
    }

    @objc private func themeBtnClicked(_ sender: NSButton) {
        if let hex = sender.identifier?.rawValue {
            onThemeSelected?(hex)
        }
    }
}
