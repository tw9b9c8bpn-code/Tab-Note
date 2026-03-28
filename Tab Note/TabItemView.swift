//
//  TabItemView.swift
//  Tab Note
//

import SwiftUI

struct TabItemView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager
    let note: TabNote
    let windowID: String

    @State private var showRenamePopover = false
    @State private var renameText = ""
    @State private var isLiveDragging = false

    private var isActive: Bool { store.selectedNoteId(in: windowID) == note.id }
    private var isDraggingThisTab: Bool { store.activeTabDrag?.noteId == note.id }

    private var activeTabColor: Color {
        switch settings.appThemeHex {
        case ThemeColor.paleYellow.rawValue: return Color(hex: "ffe500") ?? .orange
        case ThemeColor.paleGreen.rawValue:  return Color(hex: "4A8C5C") ?? .orange
        case ThemeColor.palePink.rawValue:   return Color(hex: "C47285") ?? .orange
        case ThemeColor.paleBlue.rawValue:   return Color(hex: "4A7FA8") ?? .orange
        case ThemeColor.paleGray.rawValue:   return Color(hex: "8A8A8A") ?? .orange
        case ThemeColor.palePurple.rawValue: return Color(hex: "8A5FAA") ?? .orange
        default:                             return Color(hex: "BA775B") ?? .orange
        }
    }

    private var tabColor: Color {
        isActive
            ? activeTabColor
            : (settings.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
    }

    private var textColor: Color {
        if isActive {
            return settings.appThemeHex == ThemeColor.paleYellow.rawValue
                ? Color(white: 0.12) : .white
        }
        return settings.isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 2) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundColor(textColor.opacity(0.8))
            }
            Text(note.title)
                .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                .foregroundColor(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tabColor)
                .shadow(color: isActive ? Color.black.opacity(settings.isDarkMode ? 0.3 : 0.1) : .clear,
                        radius: 2, y: 1)
        )
        .scaleEffect(isDraggingThisTab ? 0.97 : 1.0)
        .opacity(isDraggingThisTab ? 0.78 : 1.0)
        .overlay(
            Capsule()
                .stroke(
                    isDraggingThisTab ? (settings.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.25)) : .clear,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 2])
                )
        )
        .animation(.easeOut(duration: 0.12), value: isDraggingThisTab)
        .nonMovableWindow()
        .onTapGesture { store.setSelectedNoteId(note.id, in: windowID) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { _ in
                    let screenPoint = NSEvent.mouseLocation
                    if !isLiveDragging {
                        isLiveDragging = true
                        AppDelegate.shared?.beginTabDrag(
                            noteId: note.id,
                            sourceWindowID: windowID,
                            screenPoint: screenPoint
                        )
                    } else {
                        AppDelegate.shared?.updateTabDrag(
                            noteId: note.id,
                            sourceWindowID: windowID,
                            screenPoint: screenPoint
                        )
                    }
                }
                .onEnded { _ in
                    let screenPoint = NSEvent.mouseLocation
                    AppDelegate.shared?.finishTabDrag(
                        noteId: note.id,
                        sourceWindowID: windowID,
                        screenPoint: screenPoint
                    )
                    isLiveDragging = false
                }
        )
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
                    .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 160)
                HStack {
                    Button("Cancel") { showRenamePopover = false }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(.secondary)
                    Spacer()
                    Button("Rename", action: commitRename)
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered)
                }
            }
            .padding(12).frame(width: 200)
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin Tab" : "Pin Tab") { store.togglePin(id: note.id) }
            Divider()
            Button("Rename") { renameText = note.title; showRenamePopover = true }
            Button("Open in New Window") { openInNewWindow() }
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
        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { store.renameNote(id: note.id, title: t) }
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

// MARK: - Color Hex

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: Double((rgb & 0xFF0000) >> 16) / 255,
                  green: Double((rgb & 0x00FF00) >> 8)  / 255,
                  blue:  Double( rgb & 0x0000FF        ) / 255)
    }
}
