# Erdös

A macOS app for managing research experiments with integrated terminals and Claude Code sessions. Built for the Convictional research team.

Erdos gives each experiment an isolated git worktree, embedded terminal tabs, and Claude integration — so you can run multiple research threads in parallel without stepping on each other.

Named for [Paul Erdös](https://en.wikipedia.org/wiki/Paul_Erd%C5%91s) who was a prolific mathematician famous for his collected '[Erdös Problems](https://en.wikipedia.org/wiki/Paul_Erd%C5%91s#Erd%C5%91s's_problems:~:text=There%20are%20thought%20to%20be%20at%20least%20a%20thousand%20remaining%20unsolved%20problems)' and breadth of collaboration (what's your [Erdös number](https://en.wikipedia.org/wiki/Erd%C5%91s_number)?)

## Prerequisites

- **macOS 15+** (Sequoia)
- **Xcode 26.2** — install from `/Applications/Xcode-26.2.0.app` (required for SwiftData macros)
- **Claude Code CLI** — `claude` must be on your PATH (install via `npm install -g @anthropic-ai/claude-code`)

## Getting started

```bash
git clone <repo-url> erdos
cd erdos
```

### Build & run (debug)

```bash
make build    # compile only
make run      # compile + launch
```

`swift run` / `make run` launches the app directly from the terminal. Good for iterating — you'll see stdout logs inline.

### Install as an app

```bash
make install
```

This does a **release build**, bundles into `Erdos.app` (with icon and Info.plist), and copies it to `/Applications/`. You can then launch it from Spotlight or the dock like any other app.

The key difference: `make install` builds in release mode and creates a proper `.app` bundle. `make build` / `make run` are debug builds run from the terminal.

### Clean

```bash
make clean
```

## First launch

On first launch, open **Settings** (gear icon or `Cmd+,`) and configure:

| Setting | What it does | Default |
|---|---|---|
| **Repo Scan Root** | Directory scanned for git repos when creating experiments | `~/GitHub` |
| **Worktree Directory** | Where isolated worktrees are created | `~/experiment-lab-worktrees` |
| **Claude Executable Path** | Path to the `claude` CLI binary | `/usr/local/bin/claude` |
| **Default Model** | Claude model for research/drafting features | `claude-opus-4-6` |

If `claude` is installed via Homebrew or npm, it's likely at `/opt/homebrew/bin/claude` or `~/.local/bin/claude`. Check with `which claude`.

## How it works

1. **Create an experiment** — pick a repo, give it a title and hypothesis
2. **Create a worktree** — Erdos makes an isolated git branch + working directory
3. **Use the terminal** — embedded terminal tabs with full PATH (Homebrew tools work)
4. **Launch Claude** — opens a Claude Code session in the experiment's worktree
5. **Track progress** — timeline, notes, artifacts, and git changes are all visible per-experiment

Experiments go through statuses automatically: Idea -> Researching -> Planned -> Active -> Paused (and back). You can also manually set Completed or Abandoned, which locks the status from auto-updates.

A blue notification dot appears in the sidebar when a Claude session is waiting for your input.

## Developing Erdos with Claude Code

The app is a standard Swift Package Manager project — no Xcode project file needed. Claude Code works well for making changes:

```bash
cd erdos
claude
```

Useful context for Claude:

- **Architecture**: SwiftUI + SwiftData, single-window macOS app
- **Terminal integration**: SwiftTerm library, subclassed as `MonitoredTerminalView`
- **Color system**: Domain colors live on `ExperimentStatus.color` and `EventType.color` enums, plus `ErdosColors` for non-enum colors
- **Build after changes**: ask Claude to run `make build` to verify compilation
- **Install after changes**: `make install` to test as a bundled app (important for PATH/environment behavior which differs from `swift run`)

### Project structure

```
Sources/Erdos/
  Models/          # SwiftData models (Experiment, Note, Artifact, etc.)
  Views/
    Sidebar/       # Experiment list, row views
    Detail/        # Tabs: Plan, Notes, Artifacts, Timeline, Changes, Tasks
    Terminal/      # Terminal panel, MonitoredTerminalView
    Components/    # StatusBadge, CopyableLabel, ErdosColors
  Services/        # GitService, ClaudeService, StatusInferenceService
  Utilities/       # ProcessRunner, SlugGenerator, StreamJSONParser
scripts/
  bundle.sh        # Assembles .app bundle for make install
  generate-icon.swift
```
