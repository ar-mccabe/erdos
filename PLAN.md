# Draft Tasks for Convictional

## Context

We track team tasks in Convictional. Currently there's no way to generate a task description from experiment context without manually writing it. This feature adds a **Tasks tab** to Erdos that lets you one-click generate a task title + body (or an update comment) from the experiment's plan, git history, and timeline — then copy-paste into Convictional. Claude drafts the content using a few-shot prompt that matches the team's writing style.

## Approach

**Context engineering + few-shot prompt.** Gather context deterministically in Swift (git log, plan content, timeline events, experiment metadata), inject it into a focused prompt alongside few-shot examples of real Convictional tasks, and call Claude via `ClaudeService.streamResearch()`. No MCP or tool use at runtime — the prompt alone produces the right output in a single turn.

The draft is saved to `TASK-DRAFT.md` in the worktree (following the `PLAN.md` pattern), and a `taskDrafted` timeline event records the timestamp for "activity since last draft" queries.

## Files to Modify

| File | Change |
|------|--------|
| `Sources/Erdos/Models/TimelineEvent.swift` | Add `taskDrafted`, `taskUpdateDrafted` to `EventType` enum |
| `Sources/Erdos/Views/Detail/ExperimentDetailView.swift` | Add `.tasks` case to `DetailTab`, wire `TaskDraftView` |
| `Sources/Erdos/Services/ClaudeService.swift` | Add `maxTurns` parameter to `streamResearch()` (default 30) |

## File to Create

| File | Purpose |
|------|---------|
| `Sources/Erdos/Views/Detail/TaskDraftView.swift` | New ~280-line view: toolbar, empty state, streaming display, copy buttons |

## Implementation Phases

### Phase 1: Data Layer Changes

**`TimelineEvent.swift`** — Add two cases to `EventType`:
- `.taskDrafted` (label: "Task Drafted", icon: "doc.text.fill")
- `.taskUpdateDrafted` (label: "Task Update Drafted", icon: "arrow.uturn.up")

No schema migration needed — `EventType` is stored as raw `String`.

**`ClaudeService.swift`** — Add `maxTurns: Int = 30` parameter to `streamResearch()`, use it in the args array instead of hardcoded `"30"`. Task drafting calls with `maxTurns: 2` (single-turn generation, no tool use).

### Phase 2: TaskDraftView

Create `TaskDraftView.swift` following the `ResearchView` pattern (streaming via `ClaudeService`).

**States:**
- `draftTitle`, `draftBody`, `rawOutput` — parsed content
- `isRunning`, `statusMessage`, `error` — streaming state
- `currentAction: TaskAction` — `.draftTask` or `.draftUpdate`

**View hierarchy:**
```
VStack(spacing: 0)
  ├── Toolbar HStack
  │   ├── "Draft Task" button (bordered, small)
  │   ├── "Draft Update" button (borderless, caption — enabled only when prior draft exists)
  │   ├── ProgressView + elapsed + Stop (when running)
  │   ├── Spacer
  │   └── CopyableLabel for file path (when draft exists)
  ├── Divider
  └── Content
      ├── emptyState (when no draft and not running)
      └── ScrollView
          ├── Title section — title text + "Copy Title" button, in rounded card
          ├── Body section — MarkdownContentView + "Copy Body" + "Copy All" buttons, in rounded card
          └── Raw streaming text (during generation)
```

**Copy buttons** use `NSPasteboard.general` with "Copied!" feedback animation (same pattern as `CopyableLabel`). Defined as a small `CopyButton` struct inside the file.

**On appear:** loads existing `TASK-DRAFT.md` from worktree if present.

### Phase 3: Prompt Engineering

The prompt is the core of this feature. No tool use — just a well-structured prompt with few-shot examples that match Convictional's task writing conventions.

**Team writing conventions** (observed from real Convictional tasks):
- **Tone:** Direct, casual, first-person. Not corporate speak.
- **Structure varies by type:**
  - *Implementation tasks:* problem context → hypothesis/approach → scope/footprint
  - *Research tasks:* background → hypothesis → approach → what success looks like
- **Formatting:** Markdown headers, bullet points, inline links to PRs/tasks. `<br />` for spacing.
- **Length:** Ranges from 1-2 sentences (simple tasks) to detailed multi-section writeups (research). Match length to complexity.
- **Cross-references:** Link to related PRs, tasks, and prior work where relevant.

**Draft Task prompt** injects deterministically:
1. System instructions: tone, format, conventions (above), output format (`## Title` + `## Body`)
2. 2-3 few-shot examples of real task descriptions (one brief implementation, one detailed research)
3. Experiment title + hypothesis
4. `PLAN.md` content (truncated to ~3000 chars)
5. Git log on branch (`git log --oneline baseBranch..HEAD`, max 50 commits)
6. Recent timeline events (last 20)

**Draft Update prompt** injects:
1. System instructions: write a progress update comment, same tone conventions
2. 1-2 few-shot examples of update comments
3. Experiment title
4. Current `TASK-DRAFT.md` content (the original task)
5. Git commits since last `taskDrafted` event
6. Timeline events since last `taskDrafted` event

Git log is gathered via `ProcessRunner.shared.run("/usr/bin/git", arguments: [...])` directly in the view.

### Phase 4: Output Parsing & Persistence

**Parser:** Find `## Title` and `## Body` headers in the raw output, extract content between them. Parse progressively during streaming so title/body appear as Claude generates them. Fallback: if parsing fails, show raw output with "Copy All" button.

**Persistence:** Save draft to `TASK-DRAFT.md` in worktree. Record `TimelineEvent` with `.taskDrafted` or `.taskUpdateDrafted`. The timeline event timestamp is used for "since last draft" queries.

### Phase 5: Wire Up Tab

**`ExperimentDetailView.swift`:**
- Add `.tasks = "Tasks"` to `DetailTab` with icon `"checklist"`
- Add `case .tasks: TaskDraftView(experiment: experiment)` to `tabContent` switch

## Execution Flow

```
User clicks "Draft Task"
  → buildDraftTaskPrompt() gathers context (sync: plan/timeline, async: git log)
  → ClaudeService.streamResearch(prompt, maxTurns: 2)
  → Claude streams ## Title / ## Body in a single turn (no tool use)
  → StreamJSONParser yields .text events → rawOutput accumulates
  → parseDraftOutput() extracts title/body progressively → UI updates live
  → On completion: save TASK-DRAFT.md, insert TimelineEvent, show copy buttons
```

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Claude doesn't follow `## Title / ## Body` format | Prompt is explicit with few-shot examples; fallback shows raw output with copy button |
| Long plan/git history bloats prompt | Truncate plan to 3000 chars, git log to 50 commits |
| Generated tone doesn't match team style | Few-shot examples from real tasks anchor the style; iterate on examples |
| Draft is too long/short for the experiment | Prompt instructs to match length to complexity; user can regenerate |

## Verification

1. Build the app (`make build`)
2. Open an experiment with a worktree and existing PLAN.md
3. Navigate to the Tasks tab → should see empty state with "Draft Task" button
4. Click "Draft Task" → should see streaming output, then title/body with copy buttons
5. Click "Copy Title" → paste into text editor to verify
6. Click "Draft Update" → should see update based on activity since the first draft
7. Check Timeline tab → should show "Task Drafted" event

## Complexity

**Medium.** One new view file (~280 lines), three small modifications to existing files, no schema migration. Main complexity is in prompt engineering and output parsing, both of which are straightforward string operations. The streaming UX follows the established `ResearchView` pattern closely.
