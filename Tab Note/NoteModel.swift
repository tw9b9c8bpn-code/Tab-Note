//
//  NoteModel.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import Foundation
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme Color

enum ThemeColor: String, CaseIterable {
    case paleYellow = "paleYellow"
    case paleGreen = "paleGreen"
    case palePink = "palePink"
    case paleBlue = "paleBlue"
    case paleGray = "paleGray"
    case palePurple = "palePurple"

    var displayName: String {
        switch self {
        case .paleYellow: return "Pale Yellow"
        case .paleGreen: return "Pale Green"
        case .palePink: return "Pale Pink"
        case .paleBlue: return "Pale Blue"
        case .paleGray: return "Pale Gray"
        case .palePurple: return "Pale Purple"
        }
    }

    func hex(isDark: Bool) -> String {
        switch self {
        case .paleYellow: return isDark ? "2d2800" : "FEF9CA"
        case .paleGreen: return isDark ? "212A24" : "CEE5CB"
        case .palePink: return isDark ? "29031B" : "F7CFD2"
        case .paleBlue: return isDark ? "1A1A2D" : "D6E8F7"
        case .paleGray: return isDark ? "0E0E0E" : "E0E0E0"
        case .palePurple: return isDark ? "2A2230" : "DBBFE4"
        }
    }
}

// MARK: - SwiftData Models

@Model
final class TabNote {
    var id: String = UUID().uuidString
    var windowID: String = "main"
    var title: String = "New Note"
    var content: String = ""
    var rtfData: Data? = nil   // stores NSAttributedString RTF for rich-text persistence
    var colorHex: String = "C57355"
    var order: Int = 0
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(id: String = UUID().uuidString,
         windowID: String = "main",
         title: String = "New Note",
         content: String = "",
         colorHex: String = "C57355",
         order: Int = 0,
         isPinned: Bool = false) {
        self.id = id
        self.windowID = windowID
        self.title = title
        self.content = content
        self.colorHex = colorHex
        self.order = order
        self.isPinned = isPinned
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@Model
final class DeletedNote {
    var id: String = UUID().uuidString
    var title: String = ""
    var content: String = ""
    var rtfData: Data? = nil
    var colorHex: String = "C57355"
    var order: Int = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date = Date()

    init(from note: TabNote) {
        self.id = note.id
        self.title = note.title
        self.content = note.content
        self.rtfData = note.rtfData
        self.colorHex = note.colorHex
        self.order = note.order
        self.createdAt = note.createdAt
        self.modifiedAt = note.modifiedAt
        self.deletedAt = Date()
    }
}

// MARK: - NotesStore

class NotesStore: ObservableObject {
    static let mainWindowID = "main"

    struct ActiveTabDrag: Equatable {
        var noteId: String
        var sourceWindowID: String
        var screenPoint: CGPoint
        var targetWindowID: String?
    }

    @Published var notes: [TabNote] = []
    @Published var deletedNotes: [DeletedNote] = []
    @Published var selectedNoteId: String?
    @Published var renamingNoteId: String? = nil
    @Published var activeTabDrag: ActiveTabDrag?
    private var selectedNoteIdsByWindow: [String: String] = [:]
    private var tabBarFramesByWindow: [String: CGRect] = [:]

    @Published var lastDeletedNote: DeletedNote?

    private var modelContext: ModelContext?
    private var pendingSaveWork: DispatchWorkItem?

    var selectedNote: TabNote? {
        selectedNote(in: Self.mainWindowID)
    }

    func notes(in windowID: String) -> [TabNote] {
        notes
            .filter { $0.windowID == windowID }
            .sorted { $0.order < $1.order }
    }

    private func visualOrderedNotes(in windowID: String) -> [TabNote] {
        let windowNotes = notes(in: windowID)
        return windowNotes.filter(\.isPinned).sorted { $0.order < $1.order }
            + windowNotes.filter { !$0.isPinned }.sorted { $0.order < $1.order }
    }

    func visualOrderedNoteIds(in windowID: String) -> [String] {
        visualOrderedNotes(in: windowID).map(\.id)
    }

    func adjacentVisibleNoteId(for id: String, in windowID: String, preferPrevious: Bool = true) -> String? {
        let ordered = visualOrderedNotes(in: windowID)
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return nil }

        let previousID = index > 0 ? ordered[index - 1].id : nil
        let nextID = index + 1 < ordered.count ? ordered[index + 1].id : nil

        if preferPrevious {
            return previousID ?? nextID
        }
        return nextID ?? previousID
    }

    func selectedNoteId(in windowID: String) -> String? {
        if windowID == Self.mainWindowID {
            return selectedNoteId
        }
        if let id = selectedNoteIdsByWindow[windowID],
           notes.contains(where: { $0.id == id && $0.windowID == windowID }) {
            return id
        }
        return notes(in: windowID).first?.id
    }

    func selectedNote(in windowID: String) -> TabNote? {
        guard let id = selectedNoteId(in: windowID) else { return nil }
        return notes.first(where: { $0.id == id && $0.windowID == windowID })
    }

    func setSelectedNoteId(_ id: String?, in windowID: String) {
        if windowID == Self.mainWindowID {
            if selectedNoteId == id { return }
            // Notify that tab is about to change so RTF can be saved
            if selectedNoteId != nil, let outgoingId = selectedNoteId {
                NotificationCenter.default.post(name: .tabWillChange, object: outgoingId)
            }
            selectedNoteId = id
            return
        }
        let oldId = selectedNoteIdsByWindow[windowID]
        if oldId == id { return }
        if oldId != nil, let outgoingId = oldId {
            NotificationCenter.default.post(name: .tabWillChange, object: outgoingId)
        }
        selectedNoteIdsByWindow[windowID] = id
        objectWillChange.send()
    }

    func setup(context: ModelContext) {
        self.modelContext = context
        loadAll()
    }

    // MARK: - Load

    func loadAll() {
        guard let ctx = modelContext else { return }

        let noteDesc = FetchDescriptor<TabNote>(sortBy: [SortDescriptor(\.order)])
        let deletedDesc = FetchDescriptor<DeletedNote>(sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])

        notes = (try? ctx.fetch(noteDesc)) ?? []
        deletedNotes = (try? ctx.fetch(deletedDesc)) ?? []

        var didRepairWindowID = false
        for note in notes where note.windowID.isEmpty {
            note.windowID = Self.mainWindowID
            didRepairWindowID = true
        }
        if didRepairWindowID { saveImmediately() }

        if notes.isEmpty { createNote(in: Self.mainWindowID, title: "New Note") }

        if selectedNoteId == nil {
            selectedNoteId = notes(in: Self.mainWindowID).first?.id ?? notes.first?.id
        }

        let detachedWindowIDs = Set(notes.map(\.windowID)).filter { $0 != Self.mainWindowID }
        for windowID in detachedWindowIDs where selectedNoteIdsByWindow[windowID] == nil {
            selectedNoteIdsByWindow[windowID] = notes(in: windowID).first?.id
        }

        purgeExpiredDeletedNotes()
    }

    // MARK: - CRUD

    @discardableResult
    func createNote(in windowID: String = NotesStore.mainWindowID, title: String? = nil) -> String? {
        guard let ctx = modelContext else { return nil }
        let order = (notes(in: windowID).map(\.order).max() ?? -1) + 1
        let autoTitle = title ?? "\(notes(in: windowID).count + 1)"
        let note = TabNote(windowID: windowID, title: autoTitle, order: order)
        ctx.insert(note)
        saveImmediately()
        notes.append(note)
        setSelectedNoteId(note.id, in: windowID)
        return note.id
    }

    func updateNoteContent(id: String, content: String) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        note.content = content
        note.modifiedAt = Date()
        save()
    }

    func updateNoteRTF(id: String, rtfData: Data?) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        note.rtfData = rtfData
        note.modifiedAt = Date()
        save()
    }

    func renameNote(id: String, title: String) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        note.title = title
        note.modifiedAt = Date()
        saveImmediately()
        // Refresh to trigger UI update
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            objectWillChange.send()
            _ = idx
        }
    }

    /// Sets the global app theme (applies to all tabs)
    func setNoteColor(id: String, colorHex: String) {
        SettingsManager.shared.appThemeHex = colorHex
        objectWillChange.send()
    }

    func deleteNote(id: String) {
        guard let ctx = modelContext,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        let windowID = note.windowID
        let orderedBeforeDelete = visualOrderedNotes(in: windowID)
        let deletedVisualIndex = orderedBeforeDelete.firstIndex(where: { $0.id == id })

        // Move to deleted
        let deleted = DeletedNote(from: note)
        ctx.insert(deleted)
        ctx.delete(note)
        saveImmediately()

        deletedNotes.insert(deleted, at: 0)
        lastDeletedNote = deleted
        notes.remove(at: index)

        if selectedNoteId(in: windowID) == id {
            let remainingOrdered = visualOrderedNotes(in: windowID)
            let replacementIndex: Int? = {
                guard let deletedVisualIndex, !remainingOrdered.isEmpty else { return remainingOrdered.isEmpty ? nil : 0 }
                let preferredLeftIndex = deletedVisualIndex - 1
                if preferredLeftIndex >= 0, preferredLeftIndex < remainingOrdered.count {
                    return preferredLeftIndex
                }
                return remainingOrdered.isEmpty ? nil : min(deletedVisualIndex, remainingOrdered.count - 1)
            }()

            if let replacementIndex,
               replacementIndex >= 0,
               replacementIndex < remainingOrdered.count {
                let replacement = remainingOrdered[replacementIndex].id
                setSelectedNoteId(replacement, in: windowID)
            } else if windowID == Self.mainWindowID {
                createNote(in: Self.mainWindowID, title: "New Note")
            } else {
                setSelectedNoteId(nil, in: windowID)
            }
        }
    }

    func deleteSelectedNote(in windowID: String = NotesStore.mainWindowID) {
        guard let id = selectedNoteId(in: windowID) else { return }
        deleteNote(id: id)
    }

    func selectTab(at index: Int, in windowID: String = NotesStore.mainWindowID) {
        let ordered = visualOrderedNotes(in: windowID)
        guard index >= 0 && index < ordered.count else { return }
        setSelectedNoteId(ordered[index].id, in: windowID)
    }

    func togglePin(id: String) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        note.isPinned.toggle()
        note.modifiedAt = Date()
        saveImmediately()
        objectWillChange.send()
    }

    /// Commit a fully-reordered ID list produced by the hotkey engine.
    func applyOrder(_ orderedIds: [String]) {
        for (i, id) in orderedIds.enumerated() {
            if let note = notes.first(where: { $0.id == id }) { note.order = i }
        }
        saveImmediately()
        notes = notes.sorted { $0.order < $1.order }
        objectWillChange.send()
    }

    /// Move the active tab left (delta = -1) or right (delta = +1).
    /// Respects the pinned / normal boundary.
    func moveSelectedTab(by delta: Int, in windowID: String = NotesStore.mainWindowID) {
        guard let id = selectedNoteId(in: windowID) else { return }
        let ordered = visualOrderedNotes(in: windowID)
        guard let idx = ordered.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0 && newIdx < ordered.count else { return }
        // Don't cross pinned ↔ normal boundary
        guard ordered[idx].isPinned == ordered[newIdx].isPinned else { return }
        let lhs = ordered[idx]
        let rhs = ordered[newIdx]
        let lhsOrder = lhs.order
        lhs.order = rhs.order
        rhs.order = lhsOrder
        saveImmediately()
        notes = notes.sorted { $0.order < $1.order }
        objectWillChange.send()
    }

    func selectAdjacentTab(by delta: Int, in windowID: String = NotesStore.mainWindowID) {
        guard delta != 0 else { return }
        let ordered = visualOrderedNotes(in: windowID)
        guard !ordered.isEmpty else { return }

        guard let currentID = selectedNoteId(in: windowID),
              let currentIndex = ordered.firstIndex(where: { $0.id == currentID }) else {
            setSelectedNoteId(ordered.first?.id, in: windowID)
            return
        }

        let nextIndex = max(0, min(ordered.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        setSelectedNoteId(ordered[nextIndex].id, in: windowID)
    }


    func recoverLastDeletedNote() {
        guard let deleted = lastDeletedNote else { return }
        recoverNote(deleted)
        lastDeletedNote = nil
    }

    func recoverNote(_ deletedNote: DeletedNote) {
        guard let ctx = modelContext else { return }
        let order = (notes.map(\.order).max() ?? -1) + 1
        let restored = TabNote(
            id: UUID().uuidString,
            title: deletedNote.title,
            content: deletedNote.content,
            colorHex: deletedNote.colorHex,
            order: order
        )
        restored.rtfData = deletedNote.rtfData
        ctx.insert(restored)
        ctx.delete(deletedNote)
        saveImmediately()

        notes.append(restored)
        setSelectedNoteId(restored.id, in: Self.mainWindowID)
        deletedNotes.removeAll(where: { $0.id == deletedNote.id })
    }

    @discardableResult
    func moveNoteToWindow(id: String, windowID targetWindowID: String) -> String? {
        guard let note = notes.first(where: { $0.id == id }) else { return nil }
        let sourceWindowID = note.windowID
        guard sourceWindowID != targetWindowID else {
            setSelectedNoteId(id, in: targetWindowID)
            return sourceWindowID
        }

        let targetOrder = (notes(in: targetWindowID).map(\.order).max() ?? -1) + 1
        note.windowID = targetWindowID
        note.order = targetOrder
        note.modifiedAt = Date()
        saveImmediately()

        if selectedNoteId(in: sourceWindowID) == id {
            let sourceNotes = notes(in: sourceWindowID).filter { $0.id != id }
            if let replacement = sourceNotes.first?.id {
                setSelectedNoteId(replacement, in: sourceWindowID)
            } else {
                setSelectedNoteId(nil, in: sourceWindowID)
            }
        }
        setSelectedNoteId(id, in: targetWindowID)

        if sourceWindowID == Self.mainWindowID, notes(in: Self.mainWindowID).isEmpty {
            createNote(in: Self.mainWindowID, title: "New Note")
        }

        objectWillChange.send()
        return sourceWindowID
    }

    func updateTabBarFrame(_ frame: CGRect, for windowID: String) {
        if let existing = tabBarFramesByWindow[windowID],
           existing.isApproximatelyEqual(to: frame, tolerance: 0.5) {
            return
        }
        tabBarFramesByWindow[windowID] = frame
    }

    func removeTabBarFrame(for windowID: String) {
        tabBarFramesByWindow.removeValue(forKey: windowID)
    }

    func windowIDForTabBar(at screenPoint: CGPoint) -> String? {
        tabBarFramesByWindow.first(where: { $0.value.contains(screenPoint) })?.key
    }

    func beginTabDrag(noteId: String, sourceWindowID: String, screenPoint: CGPoint) {
        let next = ActiveTabDrag(
            noteId: noteId,
            sourceWindowID: sourceWindowID,
            screenPoint: screenPoint,
            targetWindowID: windowIDForTabBar(at: screenPoint)
        )
        if activeTabDrag != next {
            activeTabDrag = next
        }
    }

    func updateTabDrag(screenPoint: CGPoint) {
        guard var drag = activeTabDrag else { return }
        let nextTarget = windowIDForTabBar(at: screenPoint)
        if drag.targetWindowID == nextTarget,
           drag.screenPoint.isApproximatelyEqual(to: screenPoint, tolerance: 0.5) {
            return
        }
        drag.screenPoint = screenPoint
        drag.targetWindowID = nextTarget
        activeTabDrag = drag
    }

    func endTabDrag() {
        if activeTabDrag != nil {
            activeTabDrag = nil
        }
    }

    func exportNote(id: String, asTxt: Bool) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        let ext = asTxt ? "txt" : "md"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).\(ext)"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? note.content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Save

    /// Debounced save — coalesces rapid changes (typing, RTF updates) into one disk write.
    private func save() {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            try? self?.modelContext?.save()
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Immediate save — for structural changes (create, delete, move, pin) where data loss is unacceptable.
    private func saveImmediately() {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        try? modelContext?.save()
    }

    private func purgeExpiredDeletedNotes() {
        guard let ctx = modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let expired = deletedNotes.filter { $0.deletedAt < cutoff }
        for note in expired { ctx.delete(note) }
        deletedNotes.removeAll(where: { $0.deletedAt < cutoff })
        if !expired.isEmpty { saveImmediately() }
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance &&
        abs(minY - other.minY) <= tolerance &&
        abs(width - other.width) <= tolerance &&
        abs(height - other.height) <= tolerance
    }
}

private extension CGPoint {
    func isApproximatelyEqual(to other: CGPoint, tolerance: CGFloat) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

// MARK: - View Helpers & Extensions

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: CGFloat((rgb & 0xFF0000) >> 16)/255,
                  green: CGFloat((rgb & 0x00FF00) >> 8)/255,
                  blue: CGFloat(rgb & 0x0000FF)/255,
                  alpha: 1.0)
    }
}

extension NSImage {
    static func colorCircle(hex: String, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let nsColor = NSColor(hex: hex) {
            nsColor.setFill()
            let rect = NSRect(x: 1, y: 1, width: size - 2, height: size - 2)
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        image.unlockFocus()
        return image
    }
}

class ThemeMenuHelper {
    static func createThemeMenuItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        
        let defaultBtn = NSButton(image: NSImage.colorCircle(hex: "BA775B"), target: target, action: action)
        defaultBtn.isBordered = false
        defaultBtn.identifier = NSUserInterfaceItemIdentifier("defaultOrange")
        defaultBtn.toolTip = "Default Orange"
        stack.addArrangedSubview(defaultBtn)
        
        for color in ThemeColor.allCases {
            let btn = NSButton(image: NSImage.colorCircle(hex: color.hex(isDark: false)), target: target, action: action)
            btn.isBordered = false
            btn.identifier = NSUserInterfaceItemIdentifier(color.rawValue)
            btn.toolTip = color.displayName
            stack.addArrangedSubview(btn)
        }
        
        stack.frame = NSRect(x: 0, y: 0, width: stack.fittingSize.width, height: 32)
        item.view = stack
        return item
    }
}
