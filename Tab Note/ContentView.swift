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

// MARK: - Grid Cell State

private struct GridCellState: Equatable, Identifiable {
    let row: Int
    let col: Int
    var noteIds: [String]
    var selectedNoteId: String

    var id: String { "\(row)-\(col)" }
}

struct ContentView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager

    let windowID: String
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchRequestID = 0
    @State private var isTabAreaHidden = false

    // Grid state
    @State private var gridRows = 1
    @State private var gridCols = 1
    @State private var gridCells: [GridCellState] = []
    @State private var activeCell: String = "0-0"  // "row-col"
    @State private var preGridWidth: CGFloat?  // window width before entering grid mode

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

    private var isGridMode: Bool {
        gridRows > 1 || gridCols > 1
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
            VStack(spacing: 0) {
                if !isTabAreaHidden && !isGridMode {
                    TabBarView(windowID: windowID)
                    Divider().opacity(settings.isDarkMode ? 0.3 : 0.5)
                }

                // Search bar
                if showSearch {
                    searchBar
                }

                // Editor area — single or grid
                if isGridMode {
                    gridEditorArea
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
                  let dirStr = info["direction"] as? String,
                  let winId = info["windowID"] as? String,
                  winId == windowID else { return }
            // Map legacy split requests to grid: vertical = 1x2, horizontal = 2x1
            if isGridMode && ((dirStr == "vertical" && gridRows == 1 && gridCols == 2)
                              || (dirStr == "horizontal" && gridRows == 2 && gridCols == 1)) {
                exitGridMode()
            } else {
                let (r, c) = dirStr == "horizontal" ? (2, 1) : (1, 2)
                enterGridMode(rows: r, cols: c)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridViewRequested)) { note in
            guard let info = note.userInfo,
                  let rows = info["rows"] as? Int,
                  let cols = info["cols"] as? Int,
                  let winId = info["windowID"] as? String,
                  winId == windowID else { return }
            if rows <= 1 && cols <= 1 {
                exitGridMode()
            } else {
                enterGridMode(rows: rows, cols: cols)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gridHorizontalToggle)) { note in
            guard let winId = note.object as? String, winId == windowID else { return }
            // If already in a 1-row horizontal grid, toggle off
            if isGridMode && gridRows == 1 {
                exitGridMode()
            } else {
                // Count notes with content (cap at 5)
                let allIds = store.visualOrderedNoteIds(in: windowID)
                let withContent = allIds.filter { id in
                    guard let n = store.notes.first(where: { $0.id == id }) else { return false }
                    return !n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let cols = max(2, min(5, withContent.isEmpty ? allIds.count : withContent.count))
                enterGridMode(rows: 1, cols: cols)
            }
        }
        .onChange(of: selectedNoteID) { _, newValue in
            syncGridSelection(with: newValue)
        }
        .onReceive(store.$notes) { _ in
            reconcileGridState()
        }
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
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

    // MARK: - Grid Editor Area

    @ViewBuilder
    private var gridEditorArea: some View {
        VStack(spacing: 0) {
            ForEach(0..<gridRows, id: \.self) { row in
                if row > 0 {
                    Divider()
                }
                HStack(spacing: 0) {
                    ForEach(0..<gridCols, id: \.self) { col in
                        if col > 0 {
                            Divider()
                        }
                        let cellId = "\(row)-\(col)"
                        if let cellIndex = gridCells.firstIndex(where: { $0.id == cellId }) {
                            gridCellView(cell: gridCells[cellIndex])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gridCellView(cell: GridCellState) -> some View {
        let isActive = activeCell == cell.id
        VStack(spacing: 0) {
            GridCellTabBar(
                notes: cell.noteIds.compactMap { note(for: $0) },
                selectedNoteId: cell.selectedNoteId,
                isDarkMode: settings.isDarkMode,
                appThemeHex: settings.appThemeHex,
                windowID: windowID,
                isActiveCell: isActive,
                tabFontSize: settings.tabFontSize,
                tabHPadding: settings.tabHPadding,
                onSelectNote: { noteId in
                    selectCellNote(noteId, in: cell.id)
                },
                onAddNote: {
                    addNote(to: cell.id)
                }
            )
            Divider().opacity(settings.isDarkMode ? 0.22 : 0.34)
            noteEditorView(
                noteId: cell.selectedNoteId,
                searchQuery: isActive ? $searchQuery : .constant(""),
                searchRequestID: isActive ? searchRequestID : 0,
                onBecameActive: {
                    activateCell(cell.id)
                }
            )
            .id("grid-\(cell.id)-\(cell.selectedNoteId)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func toggleSearchBar() {
        setSearchVisible(!showSearch)
    }

    private func setSearchVisible(_ visible: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            showSearch = visible
            if !visible { searchQuery = "" }
        }
        if visible {
            DispatchQueue.main.async { isSearchFieldFocused = true }
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

    // MARK: - Grid Mode Logic

    // MARK: - Grid Note Helpers

    /// Delete every note in this window whose title is purely numeric AND whose
    /// content is blank — these are the auto-created placeholders grid mode spawns.
    private func cleanupAutoEmptyNotes() {
        let victims = store.notes.filter { n in
            guard n.windowID == windowID else { return false }
            let titleIsNumber = !n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && n.title.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy(\.isNumber)
            let contentIsEmpty = n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return titleIsNumber && contentIsEmpty
        }
        // Delete from last to first to avoid index shifting issues
        for note in victims {
            store.deleteNote(id: note.id)
        }
    }

    private func enterGridMode(rows: Int, cols: Int) {
        let totalCells = rows * cols

        // Save the single-pane width once, before first grid expansion
        if !isGridMode, let currentWidth = AppDelegate.shared?.panelWidth(for: windowID) {
            preGridWidth = currentWidth
        }

        // Resize window to fit the new column count (height unchanged)
        if let singleWidth = preGridWidth, cols > 1 {
            AppDelegate.shared?.resizePanel(windowID: windowID, toWidth: singleWidth * CGFloat(cols))
        }

        // Wipe leftover auto-empty notes from any previous grid before re-distributing
        cleanupAutoEmptyNotes()

        // Build prioritised pool: notes with content first, blank ones after
        let allNotes = store.visualOrderedNoteIds(in: windowID).compactMap { id in
            store.notes.first(where: { $0.id == id && $0.windowID == windowID })
        }
        guard !allNotes.isEmpty else { return }

        let withContent    = allNotes.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let withoutContent = allNotes.filter {  $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var availableIds   = (withContent + withoutContent).map(\.id)

        // Create placeholder notes to fill any remaining cells
        while availableIds.count < totalCells {
            if let newId = store.createNote(in: windowID) {
                availableIds.append(newId)
            } else { break }
        }

        // Distribute across cells — each cell gets at least 1 note
        var cells: [GridCellState] = []
        let perCell = max(1, availableIds.count / totalCells)
        var idIndex = 0

        for row in 0..<rows {
            for col in 0..<cols {
                let cellIndex  = row * cols + col
                let isLastCell = cellIndex == totalCells - 1
                let count  = isLastCell ? max(1, availableIds.count - idIndex) : perCell
                let slice  = Array(availableIds[idIndex..<min(idIndex + count, availableIds.count)])
                idIndex   += slice.count

                // Active note = first with content; fall back to first in slice
                let activeId = slice.first(where: { id in
                    guard let n = store.notes.first(where: { $0.id == id }) else { return false }
                    return !n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) ?? slice.first ?? ""

                cells.append(GridCellState(row: row, col: col, noteIds: slice, selectedNoteId: activeId))
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            gridRows  = rows
            gridCols  = cols
            gridCells = cells
            activeCell = "0-0"
        }

        if let firstActive = cells.first?.selectedNoteId, !firstActive.isEmpty {
            store.setSelectedNoteId(firstActive, in: windowID)
        }
    }

    private func exitGridMode() {
        cleanupAutoEmptyNotes()

        // Restore the window to its pre-split width
        if let savedWidth = preGridWidth {
            AppDelegate.shared?.resizePanel(windowID: windowID, toWidth: savedWidth)
            preGridWidth = nil
        }

        let noteId = selectedNoteID
        withAnimation(.easeInOut(duration: 0.2)) {
            gridRows  = 1
            gridCols  = 1
            gridCells = []
        }
        if let noteId, selectedNoteID != noteId {
            store.setSelectedNoteId(noteId, in: windowID)
        }
    }

    private func selectCellNote(_ noteId: String, in cellId: String) {
        if let idx = gridCells.firstIndex(where: { $0.id == cellId }) {
            gridCells[idx].selectedNoteId = noteId
        }
        activeCell = cellId
        if selectedNoteID != noteId {
            store.setSelectedNoteId(noteId, in: windowID)
        }
    }

    private func activateCell(_ cellId: String) {
        activeCell = cellId
        if let cell = gridCells.first(where: { $0.id == cellId }) {
            if selectedNoteID != cell.selectedNoteId {
                store.setSelectedNoteId(cell.selectedNoteId, in: windowID)
            }
        }
    }

    private func addNote(to cellId: String) {
        guard let noteId = store.createNote(in: windowID) else { return }
        if let idx = gridCells.firstIndex(where: { $0.id == cellId }) {
            gridCells[idx].noteIds.append(noteId)
            gridCells[idx].selectedNoteId = noteId
        }
        activeCell = cellId
    }

    private func syncGridSelection(with newSelection: String?) {
        guard isGridMode, let newSelection, note(for: newSelection) != nil else { return }

        for cell in gridCells {
            if cell.noteIds.contains(newSelection) {
                if let idx = gridCells.firstIndex(where: { $0.id == cell.id }) {
                    gridCells[idx].selectedNoteId = newSelection
                }
                activeCell = cell.id
                return
            }
        }

        reconcileGridState()
    }

    private func reconcileGridState() {
        guard isGridMode, !gridCells.isEmpty else { return }

        let orderedIds = store.visualOrderedNoteIds(in: windowID)
        let currentIdSet = Set(orderedIds)

        // Remove deleted notes from cells
        var updatedCells = gridCells
        var assignedIds = Set<String>()

        for i in updatedCells.indices {
            updatedCells[i].noteIds = updatedCells[i].noteIds.filter { currentIdSet.contains($0) && !assignedIds.contains($0) }
            assignedIds.formUnion(updatedCells[i].noteIds)
        }

        // Assign unassigned notes to active cell
        let unassigned = orderedIds.filter { !assignedIds.contains($0) }
        if !unassigned.isEmpty {
            if let idx = updatedCells.firstIndex(where: { $0.id == activeCell }) {
                updatedCells[idx].noteIds.append(contentsOf: unassigned)
            } else if !updatedCells.isEmpty {
                updatedCells[0].noteIds.append(contentsOf: unassigned)
            }
        }

        // Check if any cell is empty — if so, collapse grid if we can't fill it
        let emptyCells = updatedCells.filter { $0.noteIds.isEmpty }
        if !emptyCells.isEmpty {
            // Try to redistribute from cells with multiple notes
            for emptyCell in emptyCells {
                guard let emptyIdx = updatedCells.firstIndex(where: { $0.id == emptyCell.id }) else { continue }
                // Find a donor cell with more than 1 note
                if let donorIdx = updatedCells.firstIndex(where: { $0.noteIds.count > 1 }) {
                    let donated = updatedCells[donorIdx].noteIds.removeLast()
                    updatedCells[emptyIdx].noteIds.append(donated)
                } else {
                    // Not enough notes to fill grid — exit grid mode
                    exitGridMode()
                    return
                }
            }
        }

        // Fix selectedNoteId for each cell
        for i in updatedCells.indices {
            if !updatedCells[i].noteIds.contains(updatedCells[i].selectedNoteId) {
                updatedCells[i].selectedNoteId = updatedCells[i].noteIds.first ?? ""
            }
        }

        gridCells = updatedCells

        // Sync window-level selection with active cell
        if let cell = gridCells.first(where: { $0.id == activeCell }),
           selectedNoteID != cell.selectedNoteId {
            store.setSelectedNoteId(cell.selectedNoteId, in: windowID)
        }
    }
}

// MARK: - Grid Cell Tab Bar

private func gridCellAccentColor(for appThemeHex: String) -> Color {
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

private struct GridCellTabBar: View {
    let notes: [TabNote]
    let selectedNoteId: String
    let isDarkMode: Bool
    let appThemeHex: String
    let windowID: String
    let isActiveCell: Bool
    let tabFontSize: CGFloat
    let tabHPadding: CGFloat
    let onSelectNote: (String) -> Void
    let onAddNote: () -> Void

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
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(notes) { note in
                        GridCellTabItem(
                            note: note,
                            isActive: note.id == selectedNoteId,
                            windowID: windowID,
                            isDarkMode: isDarkMode,
                            appThemeHex: appThemeHex,
                            inactiveTabFill: inactiveTabFill,
                            inactiveTextColor: inactiveTextColor,
                            tabFontSize: tabFontSize,
                            tabHPadding: tabHPadding,
                            onSelect: { onSelectNote(note.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }

            PlusCellButton(isDarkMode: isDarkMode, action: onAddNote)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
    }
}

private struct PlusCellButton: View {
    let isDarkMode: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("+")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(
                    isHovering
                        ? (isDarkMode ? .white.opacity(0.82) : .black.opacity(0.72))
                        : (isDarkMode ? .white.opacity(0.38) : .black.opacity(0.30))
                )
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct GridCellTabItem: View {
    @EnvironmentObject var store: NotesStore

    let note: TabNote
    let isActive: Bool
    let windowID: String
    let isDarkMode: Bool
    let appThemeHex: String
    let inactiveTabFill: Color
    let inactiveTextColor: Color
    let tabFontSize: CGFloat
    let tabHPadding: CGFloat
    let onSelect: () -> Void

    @State private var showRenamePopover = false
    @State private var renameText = ""
    @State private var isHovering = false

    private var tabFill: Color {
        if isActive { return gridCellAccentColor(for: appThemeHex) }
        if isHovering {
            return isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
        }
        return inactiveTabFill
    }

    private var textColor: Color {
        if isActive {
            return appThemeHex == ThemeColor.paleYellow.rawValue
                ? Color(white: 0.12)
                : .white
        }
        return isHovering
            ? (isDarkMode ? .white.opacity(0.88) : .black.opacity(0.78))
            : inactiveTextColor
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 3) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7))
                }
                Text(note.title)
                    .lineLimit(1)
            }
            .font(.system(size: tabFontSize, weight: isActive ? .semibold : .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, tabHPadding)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tabFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
