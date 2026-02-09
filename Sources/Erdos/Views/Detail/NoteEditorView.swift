import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @State private var isPreview = false

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
        }
        .onChange(of: note.title) { _, _ in
            note.updatedAt = Date()
        }
    }
}
