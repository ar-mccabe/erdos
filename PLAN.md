# Artifact Cleanups: Focused Artifacts Tab with Content Preview

## Context

The Artifacts tab currently scans and lists **every file** in the worktree (via `FileManager.enumerator`), producing a noisy flat list with no way to click into files and see their content. This makes it hard to quickly see what matters for a running experiment.

The goal is to make Artifacts a focused, useful view showing only **experiment-relevant files** (PLAN.md, notes, changed files) with **inline content preview** when clicking an item.

## Approach

Rewrite `ArtifactsView` using the same HSplitView (list | detail) pattern as `ChangesView`. Replace the full-worktree scan with three focused sources:

1. **Documents** — Well-known files like PLAN.md, CLAUDE.md
2. **Notes** — The experiment's notes (read-only preview; editing stays in Notes tab)
3. **Changed Files** — Files changed on branch vs base (full content, not patches)

Reuse `MarkdownContentView` for .md files and notes, monospaced `Text` for code/config files.

## Files to Modify

| File | Change |
|------|--------|
| `Sources/Erdos/Services/GitService.swift` | Add `ChangedFile` struct + `getChangedFiles(path:baseBranch:)` method |
| `Sources/Erdos/Views/Detail/ArtifactsView.swift` | Full rewrite: HSplitView layout, sectioned list, content preview |

No changes needed to `Artifact.swift` or `Experiment.swift` — the Artifact model stays in the schema but the view no longer reads from `experiment.artifacts` or calls `scanWorktree()`.

## Implementation Steps

### Step 1: Add `getChangedFiles` to GitService

Add a `ChangedFile` struct and method to `GitService.swift`:

- `ChangedFile` has `path: String` and `source: ChangeSource` (committed/uncommitted/both)
- `getChangedFiles(path:baseBranch:)` runs two git commands:
  - `git diff --name-only <baseBranch>...HEAD` — files changed in branch commits
  - `git status --porcelain=v1` — uncommitted changes
- Merges both into a deduplicated sorted list
- Falls back to uncommitted-only if `baseBranch` is not found (handles missing remote)

### Step 2: Define `ArtifactItem` enum in ArtifactsView

A lightweight enum that unifies the three sources into one selectable type:

```
enum ArtifactItem: Identifiable, Hashable {
    case document(path: String, name: String)
    case note(Note)
    case changedFile(GitService.ChangedFile)
}
```

Each case provides `displayName`, `icon`, and `subtitle` for the list row.

### Step 3: Rewrite ArtifactsView body

**Layout** — Follow the `ChangesView` pattern exactly:
```
VStack(spacing: 0) {
    toolbar        // counts: "2 docs · 3 notes · 5 changed"
    Divider()
    HSplitView {
        artifactList      // sectioned List (Documents / Notes / Changed Files)
            .frame(minWidth: 180, idealWidth: 240)
        contentPreview    // markdown or monospaced text viewer
            .frame(minWidth: 300)
    }
}
```

**State:**
- `changedFiles: [GitService.ChangedFile]` — refreshed from git
- `documentPaths: [(path: String, name: String)]` — discovered on refresh
- `selectedItem: ArtifactItem?` — drives content preview
- `previewContent: String` — loaded async on selection change
- `autoRefreshTimer: Timer?` — 3-second interval (same as ChangesView)

**Artifact list** — Three `Section`s with sidebar list style. Each row: icon + name + subtitle (path or content snippet). Context menu "Open in Finder" for documents and changed files.

**Content preview** — Routes by selection:
- `.md` files and notes → `MarkdownContentView(content:)` (existing component)
- All other files → monospaced `Text` in `ScrollView` with `.textSelection(.enabled)`
- No selection → "Select an artifact to preview"
- File not found → "File may have been deleted"
- File > 500KB → "File too large to preview"

### Step 4: Implement data loading

- `refresh()` — discovers documents + calls `getChangedFiles`, runs on `.task` and 3s timer
- `discoverDocuments(in:)` — checks for known files: PLAN.md, CLAUDE.md, README.md
- `loadContent(for:)` — reads file content async on selection change; notes use `note.content` directly
- Auto-refresh timer: start `onAppear`, invalidate `onDisappear` (same pattern as ChangesView)

### Step 5: Edge case handling

- **Deleted files**: git may report files that no longer exist — show "File not found" message
- **Binary files**: `String(contentsOfFile:)` will throw — show "Cannot read file"
- **baseBranch not found**: fall back to uncommitted files only
- **Empty worktree**: show "No Artifacts" empty state
- **No worktree**: show "Create a worktree" empty state (same as current)

## What's NOT Changing

- `Artifact.swift` model — stays in SwiftData schema, no migration needed
- `ExperimentDetailView.swift` tab routing — still renders `ArtifactsView(experiment:)`
- `MarkdownContentView` — reused as-is
- `ChangesView` — untouched, still shows patches/diffs
- Notes tab — still the place for editing notes

## Verification

1. Build the app (`Cmd+B`)
2. Open an experiment with a worktree and branch
3. Navigate to Artifacts tab — should show three sections (Documents / Notes / Changed Files)
4. Click PLAN.md → should render markdown in right pane
5. Click a note → should render note content as markdown
6. Click a changed .py/.swift file → should show full file content in monospaced text
7. Make a file change in terminal → should appear in "Changed Files" within 3 seconds
8. Test with experiment that has no worktree → should show empty state

## Complexity

Low-medium. Two files modified, ~200 lines rewritten in ArtifactsView, ~30 lines added to GitService. All patterns are borrowed from existing `ChangesView` code.
