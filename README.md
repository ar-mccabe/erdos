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
5. **Track progress** — timeline, notes, artifacts, git changes, and GitHub PRs are all visible per-experiment
6. **Note sync** — notes are synced to `.erdos/notes/` in the worktree, so Claude can read and write them
7. **Cleanup** — when an experiment is completed or abandoned, Erdos can archive files and remove the worktree

Experiments have 11 statuses: Idea, Researching, Planned, Paused, Blocked, Implementing, Testing, In Review, Merged, Completed, Abandoned. Light auto-inference moves experiments from Idea to Researching (when a Claude session launches) and to Planned (when a plan is detected). All other transitions are manual. Completed, Abandoned, and Merged are terminal — auto-inference won't touch them.

A yellow notification dot appears in the sidebar when a Claude session is waiting for your input.

## Repo configuration (`.erdos.yml`)

Repos can declare a `.erdos.yml` file in their root to configure what happens when Erdos creates a worktree. This is useful for copying gitignored files (like `.env` secrets) into new worktrees automatically.

```yaml
# .erdos.yml
worktree:
  copy_files:           # gitignored files to copy from main repo into worktrees
    - .env*             # trailing wildcard — copies all files matching the prefix
    - experiments/.env* # works in subdirectories too
  env_var:
    from_branch: true           # generate an ENV name from the branch name
    copy_base: .env.development # copy this file as .env.<envName> in the worktree
```

All fields are optional. If no `.erdos.yml` exists, worktree creation works as normal with no extra steps.

**`copy_files`** — Each entry is either an explicit file path or a trailing-wildcard pattern. Files are copied from the main repo into the worktree, preserving subdirectory structure. Missing files are silently skipped.

**`env_var`** — When `from_branch` is true, Erdos generates an env var name from the branch (replacing hyphens with underscores, stripping special characters). If `copy_base` is set, that file is copied as `.env.<envName>` in the worktree. The env var name is shown in the experiment header as a copyable `ENV=<name>` label.

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
    Detail/        # Tabs: Plan, Notes, Artifacts, Timeline, Changes, Pull Requests, Tasks
    Terminal/      # Terminal panel, MonitoredTerminalView
    Components/    # StatusBadge, CopyableLabel, ErdosColors
  Services/        # GitService, GitHubService, ClaudeService, NoteSyncService, CleanupService, WorktreeSetupService, StatusInferenceService, FileWatcherService
  Utilities/       # ProcessRunner, SlugGenerator, StreamJSONParser
scripts/
  bundle.sh        # Assembles .app bundle for make install
  generate-icon.swift
```
