import SwiftUI
import SwiftData

struct NotesListView: View {
    @Bindable var experiment: Experiment
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNote: Note?
    @State private var filterType: NoteType?

    var body: some View {
        HSplitView {
            // Notes list
            VStack(spacing: 0) {
                // Filter bar
                HStack {
                    Picker("Filter", selection: $filterType) {
                        Text("All").tag(nil as NoteType?)
                        ForEach(NoteType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type as NoteType?)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        Button("Delete", role: .destructive) {
                            deleteNote(note)
                        }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 250)

            // Editor
            if let note = selectedNote {
                NoteEditorView(note: note)
            } else {
                ContentUnavailableView(
                    "Select a Note",
                    systemImage: "note.text",
                    description: Text("Select a note to edit, or click + to create one.")
                )
            }
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

        selectedNote = note
    }

    private func deleteNote(_ note: Note) {
        if selectedNote == note { selectedNote = nil }
        modelContext.delete(note)
    }
}
