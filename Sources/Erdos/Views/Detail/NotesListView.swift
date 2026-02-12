import SwiftUI
import SwiftData
import AppKit

struct NotesListView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNote: Note?
    @State private var filterType: NoteType?
    @State private var pollTimer: Timer?

    private var worktreePath: String? { experiment.worktreePath }

    var body: some View {
        Group {
            if selectedNote != nil {
                HSplitView {
                    notesList
                        .frame(minWidth: 200, idealWidth: 250)
                    if let note = selectedNote {
                        NoteEditorView(note: note, worktreePath: worktreePath) {
                            deleteNote(note)
                        }
                    }
                }
            } else {
                notesList
            }
        }
        .task {
            initialExport()
            startPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    @ViewBuilder
    private var notesList: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Filter", selection: $filterType) {
                    Text("All").tag(nil as NoteType?)
                    ForEach(NoteType.allCases) { type in
                        Label(type.label, systemImage: type.icon).tag(type as NoteType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
                .labelsHidden()

                Spacer()

                Button {
                    addNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)

            Divider()

            List(filteredNotes, selection: $selectedNote) { note in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(ErdosColors.pinnedIcon)
                        }
                        Text(note.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: note.noteType.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(note.content.prefix(80))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(coarseRelativeTime(since: note.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .tag(note)
                .contextMenu {
                    Button(note.isPinned ? "Unpin" : "Pin") {
                        note.isPinned.toggle()
                    }
                    Divider()
                    if let wt = worktreePath {
                        let filename = NoteSyncService.filename(for: note)
                        Button("Copy Note") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("# \(note.title)\n\n\(note.content)", forType: .string)
                        }
                        Button("Copy @-reference") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("@\(wt)/.erdos/notes/\(filename)", forType: .string)
                        }
                        Divider()
                    }
                    Button("Delete", role: .destructive) {
                        deleteNote(note)
                    }
                }
            }
        }
    }

    private var filteredNotes: [Note] {
        let notes = experiment.notes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        if let filter = filterType {
            return notes.filter { $0.noteType == filter }
        }
        return notes
    }

    private func addNote() {
        let noteType = filterType ?? .general
        let note = Note(title: "New Note", noteType: noteType)
        note.experiment = experiment
        modelContext.insert(note)

        let event = TimelineEvent(eventType: .noteAdded, summary: "Note added: New Note")
        event.experiment = experiment
        modelContext.insert(event)

        // Export the new note to disk
        if let wt = worktreePath {
            appState.noteSyncService.exportNote(note, worktreePath: wt)
        }

        selectedNote = note
    }

    private func deleteNote(_ note: Note) {
        if selectedNote == note { selectedNote = nil }

        // Delete the corresponding file on disk
        if let wt = worktreePath {
            appState.noteSyncService.deleteNoteFile(note, worktreePath: wt)
        }

        modelContext.delete(note)
    }

    private func initialExport() {
        guard worktreePath != nil else { return }
        appState.noteSyncService.exportAllNotes(experiment: experiment)
    }

    private func coarseRelativeTime(since date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr\(hours == 1 ? "" : "s"), \(minutes % 60) mins" }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s"), \(hours % 24) hrs"
    }

    private func startPolling() {
        guard let wt = worktreePath else { return }
        appState.noteSyncService.ensureNotesDirectory(worktreePath: wt)

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                guard !appState.noteSyncService.isWriting else { return }
                let events = appState.noteSyncService.importChanges(
                    worktreePath: wt,
                    experiment: experiment,
                    context: modelContext
                )
                for event in events {
                    let timelineEvent = TimelineEvent(
                        eventType: .noteUpdatedFromFile,
                        summary: event.summary
                    )
                    timelineEvent.experiment = experiment
                    modelContext.insert(timelineEvent)
                }
            }
        }
    }
}
