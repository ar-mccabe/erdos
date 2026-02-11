# Plan: Fix Notes Tab UI Issues

## Context

The Notes tab in Erdos has two usability problems:
1. The segmented filter picker (All/General/Hypothesis/Observation/Decision/Blocker) is crammed into a ~250px left panel, truncating the labels and hiding the "+" new note button — forcing users to resize the pane just to filter or create notes.
2. When no note is selected (e.g. first entering the tab), the notes list is confined to the narrow left panel of an HSplitView while the right panel shows a mostly-empty placeholder, wasting the available tab space.

## Approach

**Only one file needs changes:** `Sources/Erdos/Views/Detail/NotesListView.swift`

### Fix 1: Replace segmented picker with menu picker

Change `.pickerStyle(.segmented)` to `.pickerStyle(.menu)` and add a `maxWidth` constraint. This collapses the 6-segment control into a single dropdown button, leaving room for the "+" button. This is consistent with how `NoteEditorView` already renders its type picker (`.pickerStyle(.menu)` at line 22).

**Lines 15-33 — change the filter bar:**
```swift
HStack {
    Picker("Filter", selection: $filterType) {
        Text("All").tag(nil as NoteType?)
        ForEach(NoteType.allCases) { type in
            Label(type.label, systemImage: type.icon).tag(type as NoteType?)
        }
    }
    .pickerStyle(.menu)          // was .segmented
    .frame(maxWidth: 160)        // prevent over-expansion
    .labelsHidden()

    Spacer()

    Button { addNote() } label: {
        Image(systemName: "plus")
    }
    .buttonStyle(.borderless)
}
.padding(8)
```

### Fix 2: Full-width notes list when no note is selected

Extract the notes list VStack into a `notesList` computed property, then conditionally render:
- **No note selected** → show `notesList` at full width (no HSplitView)
- **Note selected** → show `HSplitView` with `notesList` (constrained) + `NoteEditorView`

```swift
var body: some View {
    if selectedNote != nil {
        HSplitView {
            notesList
                .frame(minWidth: 200, idealWidth: 250)
            if let note = selectedNote {
                NoteEditorView(note: note)
            }
        }
    } else {
        notesList
    }
}

@ViewBuilder
private var notesList: some View {
    VStack(spacing: 0) {
        // filter bar (from Fix 1)
        // Divider
        // List(filteredNotes, selection: $selectedNote) { ... }
    }
}
```

The existing `deleteNote` method already sets `selectedNote = nil`, so deleting the active note correctly transitions back to the full-width list.

## Implementation Steps

1. Change `.pickerStyle(.segmented)` → `.pickerStyle(.menu)` and add `.frame(maxWidth: 160)` on the filter picker
2. Extract the notes list VStack into a `@ViewBuilder private var notesList` computed property
3. Rewrite `body` to conditionally render full-width list vs HSplitView based on `selectedNote`
4. Build and verify

## Verification

- Build the project (`swift build` or Xcode build)
- Open the Notes tab on an experiment — the notes list should be full-width when no note is selected
- Click a note — the HSplitView should appear with the editor on the right
- The filter dropdown should be accessible at any panel width without truncation
- The "+" button should always be visible
- Delete the selected note — should transition back to full-width list

## Risks

- **SwiftUI HSplitView state:** Toggling between HSplitView and plain VStack could cause SwiftUI to lose the split divider position between transitions. This is acceptable since the divider resets to ideal width each time.
- **Low risk overall:** This is a single-file change with no model or data changes.

## Complexity

Low — approximately 30 lines changed in one file.
