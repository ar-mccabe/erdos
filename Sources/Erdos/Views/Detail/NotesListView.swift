import SwiftUI
import SwiftData
import AppKit

struct NotesListView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNote: Note?
    @State private var filterType: NoteType?
    @State private var fileWatcher = FileWatcherService()

    private var worktreePath: String? { experiment.worktreePath }

    var body: some View {
        if selectedNote != nil {
            HSplitView {
                notesList
                    .frame(minWidth: 200, idealWidth: 250)
                if let note = selectedNote {
                    NoteEditorView(note: note, worktreePath: worktreePath)
                }
            }
        } else {
            notesList
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
                    Text(note.updatedAt, style: .relative)
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
        .task {
            await initialSync()
        }
        .onDisappear {
            fileWatcher.stopWatching()
        }
    }

    private var filteredNotes: [Note] {
        let notes = experiment.notes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
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

    private func initialSync() async {
        guard let wt = worktreePath else { return }

        // Export all notes to disk on appear
        appState.noteSyncService.exportAllNotes(experiment: experiment)

        // Start watching .erdos/notes/ for external changes
        let notesDir = appState.noteSyncService.ensureNotesDirectory(worktreePath: wt)
        fileWatcher.onFilesChanged = { [weak appState] in
            guard let appState, !appState.noteSyncService.isWriting else { return }
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
        fileWatcher.startWatching(path: notesDir)
    }
}
