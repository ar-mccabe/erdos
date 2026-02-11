import SwiftUI
import AppKit

struct NoteEditorView: View {
    @Bindable var note: Note
    var worktreePath: String?
    @Environment(AppState.self) private var appState
    @State private var isPreview = false
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.headline)

                Spacer()

                Picker("Type", selection: $note.noteType) {
                    ForEach(NoteType.allCases) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Button {
                    note.isPinned.toggle()
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)

                Button(isPreview ? "Edit" : "Preview") {
                    isPreview.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(8)

            // Copy buttons and file path
            if let wt = worktreePath {
                HStack(spacing: 8) {
                    let filename = NoteSyncService.filename(for: note)
                    CopyableLabel(
                        text: ".erdos/notes/\(filename)",
                        icon: "doc.text",
                        display: ".erdos/notes/\(filename)",
                        font: .caption2,
                        color: .tertiary
                    )

                    Spacer()

                    CopyNoteButton(text: "# \(note.title)\n\n\(note.content)", label: "Copy Note")
                    CopyNoteButton(text: "@\(wt)/.erdos/notes/\(filename)", label: "Copy @-ref")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            Divider()

            if isPreview {
                MarkdownContentView(content: note.content)
            } else {
                TextEditor(text: $note.content)
                    .font(.system(.body, design: .monospaced))
                    .padding(4)
            }
        }
        .onChange(of: note.content) { _, _ in
            note.updatedAt = Date()
            scheduleDebouncedExport()
        }
        .onChange(of: note.title) { _, _ in
            note.updatedAt = Date()
            scheduleDebouncedExport()
        }
        .onChange(of: note.noteType) { _, _ in
            scheduleDebouncedExport()
        }
        .onChange(of: note.isPinned) { _, _ in
            scheduleDebouncedExport()
        }
    }

    private func scheduleDebouncedExport() {
        guard let wt = worktreePath else { return }
        exportTask?.cancel()
        exportTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            appState.noteSyncService.exportNote(note, worktreePath: wt)
        }
    }
}

// MARK: - CopyNoteButton

private struct CopyNoteButton: View {
    let text: String
    let label: String
    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
            }
        } label: {
            if showCopied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Label(label, systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
