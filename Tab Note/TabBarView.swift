//
//  TabBarView.swift
//  Tab Note
//

import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager

    let windowID: String
    @State private var availableWidth: CGFloat = 400

    init(windowID: String = NotesStore.mainWindowID) {
        self.windowID = windowID
    }

    private let tabSpacing: CGFloat = 3
    private let rowSpacing:  CGFloat = 3
    private var maxRows: Int { settings.maxTabRows }

    var pinnedNotes: [TabNote] { store.notes(in: windowID).filter(\.isPinned) }
    var normalNotes: [TabNote] { store.notes(in: windowID).filter { !$0.isPinned } }
    var allNotes:    [TabNote] { pinnedNotes + normalNotes }

    func tabWidth(_ note: TabNote) -> CGFloat {
        max(26, CGFloat(note.title.count) * 5.5 + 16 + (note.isPinned ? 10 : 0))
    }

    struct RowLayout { var rows: [[TabNote]]; var overflowNotes: [TabNote] }

    func computeLayout(width: CGFloat) -> RowLayout {
        let plusW: CGFloat = 30, overflowW: CGFloat = 30, pinnedSepW: CGFloat = 10
        var rows: [[TabNote]] = [[]], rowWidths: [CGFloat] = [0], overflow: [TabNote] = []
        for (i, note) in allNotes.enumerated() {
            let isFirstNormal = !note.isPinned && i > 0 && allNotes[i-1].isPinned
            let w = tabWidth(note) + tabSpacing + (isFirstNormal ? pinnedSepW : 0)
            let row = rows.count - 1
            let limit: CGFloat = row == maxRows - 1
                ? width - plusW - tabSpacing - overflowW - tabSpacing
                : width
            if rowWidths[row] + w > limit && rowWidths[row] > 0 {
                if row + 1 < maxRows {
                    rows.append([]); rowWidths.append(0)
                    rows[rows.count-1].append(note); rowWidths[rowWidths.count-1] += tabWidth(note) + tabSpacing
                } else { overflow.append(note) }
            } else { rows[row].append(note); rowWidths[row] += w }
        }
        return RowLayout(rows: rows.filter { !$0.isEmpty }, overflowNotes: overflow)
    }

    var body: some View {
        let layout = computeLayout(width: max(0, availableWidth - 16))
        let isDropTarget = store.activeTabDrag?.targetWindowID == windowID

        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { rowIdx, row in
                let isLastRow = rowIdx == layout.rows.count - 1
                HStack(spacing: tabSpacing) {
                    ForEach(row) { note in
                        let idx = allNotes.firstIndex { $0.id == note.id } ?? 0
                        let isFirstNormal = !note.isPinned && idx > 0 && allNotes[idx-1].isPinned
                        if isFirstNormal { Spacer().frame(width: 6) }
                        TabItemView(note: note, windowID: windowID)
                    }
                    if isLastRow {
                        if !layout.overflowNotes.isEmpty {
                            OverflowMenuButton(windowID: windowID, overflowNotes: layout.overflowNotes)
                        }
                        PlusButton(windowID: windowID)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    settings.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
                .opacity(isDropTarget ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isDropTarget)
        )
        .overlay(alignment: .topLeading) {
            if isDropTarget {
                Text("Drop to merge tab")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(settings.isDarkMode ? .white.opacity(0.9) : .black.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(settings.isDarkMode ? Color.black.opacity(0.35) : Color.white.opacity(0.85))
                    )
                    .padding(.leading, 8)
                    .padding(.top, -8)
                    .transition(.opacity)
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { availableWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in availableWidth = w }
        })
        .background(
            ScreenFrameReporter { frame in
                store.updateTabBarFrame(frame, for: windowID)
            }
        )
        .onDisappear {
            store.removeTabBarFrame(for: windowID)
        }
    }
}

// MARK: - Overflow Menu Button

struct OverflowMenuButton: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager
    let windowID: String
    let overflowNotes: [TabNote]

    var body: some View {
        Menu {
            ForEach(overflowNotes) { note in
                Button { store.setSelectedNoteId(note.id, in: windowID) } label: {
                    Label(note.title, systemImage: note.isPinned ? "pin.fill" : "note.text")
                }
            }
        } label: {
            Text("•••")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(settings.isDarkMode ? .white.opacity(0.6) : .black.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(settings.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07)))
        }
        .menuStyle(.borderlessButton).fixedSize().nonMovableWindow()
    }
}

// MARK: - Plus Button

struct PlusButton: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager
    let windowID: String
    @State private var isHovering = false

    var body: some View {
        Button { store.createNote(in: windowID) } label: {
            Text("+")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(
                    isHovering
                        ? (settings.isDarkMode ? .white.opacity(0.82) : .black.opacity(0.72))
                        : (settings.isDarkMode ? .white.opacity(0.38) : .black.opacity(0.30))
                )
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .nonMovableWindow()
    }
}
