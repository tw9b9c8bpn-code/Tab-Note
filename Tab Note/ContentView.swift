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

struct ContentView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var settings: SettingsManager

    let windowID: String
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchRequestID = 0
    @State private var isTabAreaHidden = false
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
                if !isTabAreaHidden {
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

                NoteEditorView(
                    text: editorBinding,
                    searchQuery: $searchQuery,
                    windowID: windowID,
                    noteId: selectedNoteID,
                    searchRequestID: searchRequestID,
                    settings: settings,
                    onThemeSelected: { hex in setNoteColor(hex) },
                    onRTFChange: { rtf in
                        if let id = selectedNoteID {
                            store.updateNoteRTF(id: id, rtfData: rtf)
                        }
                    },
                    initialRTF: selectedNote?.rtfData
                )
                .id(selectedNoteID ?? "no-note")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
