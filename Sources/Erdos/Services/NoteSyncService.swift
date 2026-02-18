import Foundation
import SwiftData
import Yams

@Observable
@MainActor
final class NoteSyncService {

    /// Guard to prevent the file watcher from re-importing our own writes.
    private(set) var isWriting = false
    /// Guard to suppress onChange re-exports during import.
    private(set) var isSyncing = false
    /// Tracks when Erdos last wrote each note file, for freshness checks.
    private var lastExportedAt: [UUID: Date] = [:]
    /// Content last imported from disk, so onChange can detect import-triggered mutations.
    private(set) var lastImportedContent: [UUID: String] = [:]
    /// Title last imported from disk, so onChange can detect import-triggered mutations.
    private(set) var lastImportedTitle: [UUID: String] = [:]

    private static let notesDir = ".erdos/notes"

    // MARK: - Export (Erdos → Disk)

    func exportNote(_ note: Note, worktreePath: String) {
        let dirPath = ensureNotesDirectory(worktreePath: worktreePath)
        let filename = Self.filename(for: note)
        let filePath = (dirPath as NSString).appendingPathComponent(filename)

        // Freshness guard: skip if file has been externally modified since our last export
        if let lastExport = lastExportedAt[note.id],
           let fileMtime = Self.fileModificationDate(filePath),
           fileMtime > lastExport {
            return
        }

        // If the title changed, the slug changed — find and remove the old file by scanning for this note's id
        removeOldFile(for: note, in: dirPath, currentFilename: filename)

        let content = Self.renderMarkdown(for: note)

        isWriting = true
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        lastExportedAt[note.id] = Date()

        // Brief delay before clearing the guard so the file watcher event can be ignored
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWriting = false
        }
    }

    func exportAllNotes(experiment: Experiment) {
        guard let worktreePath = experiment.worktreePath else { return }
        let dirPath = ensureNotesDirectory(worktreePath: worktreePath)

        isWriting = true

        // Write all current notes
        for note in experiment.notes {
            let filename = Self.filename(for: note)
            let filePath = (dirPath as NSString).appendingPathComponent(filename)

            // Freshness guard: skip if file has been externally modified since our last export
            if let lastExport = lastExportedAt[note.id],
               let fileMtime = Self.fileModificationDate(filePath),
               fileMtime > lastExport {
                continue
            }

            removeOldFile(for: note, in: dirPath, currentFilename: filename)
            let content = Self.renderMarkdown(for: note)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            lastExportedAt[note.id] = Date()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWriting = false
        }
    }

    /// Export only notes that don't already have a file on disk.
    func exportMissingNotes(experiment: Experiment) {
        guard let worktreePath = experiment.worktreePath else { return }
        let dirPath = ensureNotesDirectory(worktreePath: worktreePath)
        let fm = FileManager.default

        // Collect IDs of notes already on disk
        var diskNoteIds = Set<UUID>()
        if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
            for file in files where file.hasSuffix(".md") {
                let fullPath = (dirPath as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8),
                   let frontmatter = Self.parseFrontmatter(from: content),
                   let idString = frontmatter["id"] as? String,
                   let id = UUID(uuidString: idString) {
                    diskNoteIds.insert(id)
                }
            }
        }

        // Export only notes not already on disk
        let notesToExport = experiment.notes.filter { !diskNoteIds.contains($0.id) }
        guard !notesToExport.isEmpty else { return }

        isWriting = true
        for note in notesToExport {
            let filename = Self.filename(for: note)
            let filePath = (dirPath as NSString).appendingPathComponent(filename)
            let content = Self.renderMarkdown(for: note)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            lastExportedAt[note.id] = Date()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWriting = false
        }
    }

    func deleteNoteFile(_ note: Note, worktreePath: String) {
        let dirPath = (worktreePath as NSString).appendingPathComponent(Self.notesDir)
        let fm = FileManager.default

        isWriting = true

        // Find file by id scan (most reliable)
        if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
            for file in files where file.hasSuffix(".md") {
                let fullPath = (dirPath as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8),
                   let frontmatter = Self.parseFrontmatter(from: content),
                   let idString = frontmatter["id"] as? String,
                   UUID(uuidString: idString) == note.id {
                    try? fm.removeItem(atPath: fullPath)
                    break
                }
            }
        }

        lastExportedAt.removeValue(forKey: note.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWriting = false
        }
    }

    // MARK: - Import (Disk → Erdos)

    /// Scan `.erdos/notes/`, parse frontmatter, create/update SwiftData notes.
    /// Returns an array of (summary, isNew) for timeline events.
    func importChanges(
        worktreePath: String,
        experiment: Experiment,
        context: ModelContext
    ) -> [(summary: String, isNew: Bool)] {
        let dirPath = (worktreePath as NSString).appendingPathComponent(Self.notesDir)
        let fm = FileManager.default
        var events: [(summary: String, isNew: Bool)] = []

        guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { return events }

        isSyncing = true

        // Build lookup of existing notes by id
        let existingNotes = Dictionary(uniqueKeysWithValues: experiment.notes.map { ($0.id, $0) })

        for file in files where file.hasSuffix(".md") {
            let fullPath = (dirPath as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            let frontmatter = Self.parseFrontmatter(from: content)
            let body = Self.extractBody(from: content)

            let hasFileId = frontmatter?["id"] as? String != nil
            let fileId: UUID
            if let idString = frontmatter?["id"] as? String, let parsed = UUID(uuidString: idString) {
                fileId = parsed
            } else {
                // No id — check if we already imported this file path before
                // by scanning existing notes for a matching title to avoid duplicates
                let fileTitle = (frontmatter?["title"] as? String) ?? Self.titleFromFilename(file)
                if experiment.notes.contains(where: { $0.title == fileTitle }) {
                    continue
                }
                fileId = UUID()
            }

            let fileTitle = (frontmatter?["title"] as? String) ?? Self.titleFromFilename(file)
            let fileType = (frontmatter?["type"] as? String).flatMap { NoteType(rawValue: $0) } ?? .general
            let filePinned = (frontmatter?["pinned"] as? Bool) ?? false
            let fileUpdated = Self.parseDate(frontmatter?["updated"]) ?? Self.fileModificationDate(fullPath)

            if let existing = existingNotes[fileId] {
                // Detect whether the file was externally modified
                let shouldImport: Bool
                if let lastExport = lastExportedAt[fileId],
                   let fileMtime = Self.fileModificationDate(fullPath) {
                    // We have export tracking — use mtime (reliable even if frontmatter date unchanged)
                    shouldImport = fileMtime > lastExport
                } else if let fileDate = fileUpdated {
                    // No export record (cold start) — fall back to frontmatter date
                    shouldImport = fileDate > existing.updatedAt
                } else {
                    shouldImport = false
                }

                if shouldImport {
                    // Track imported content to suppress onChange re-export
                    lastImportedContent[fileId] = body
                    lastImportedTitle[fileId] = fileTitle
                    existing.title = fileTitle
                    existing.content = body
                    existing.noteType = fileType
                    existing.isPinned = filePinned
                    existing.updatedAt = fileUpdated ?? Date()
                    // Record file mtime so subsequent user edits can export without being blocked
                    lastExportedAt[fileId] = Self.fileModificationDate(fullPath) ?? Date()
                    events.append((summary: "Note updated from file: \(fileTitle)", isNew: false))
                }
            } else {
                // New note — Claude or someone created a file
                let note = Note(title: fileTitle, content: body, noteType: fileType, isPinned: filePinned)
                if hasFileId {
                    note.id = fileId
                }
                if let created = Self.parseDate(frontmatter?["created"]) {
                    note.createdAt = created
                }
                if let updated = fileUpdated {
                    note.updatedAt = updated
                }
                note.experiment = experiment
                context.insert(note)
                events.append((summary: "Note created from file: \(fileTitle)", isNew: true))

                // Write back frontmatter with id so subsequent polls can match this note
                let updatedContent = Self.renderMarkdown(for: note)
                isWriting = true
                try? updatedContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                lastExportedAt[note.id] = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.isWriting = false
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isSyncing = false
        }

        return events
    }

    // MARK: - Import Tracking

    /// Clear tracked import content for a note after onChange has consumed it.
    func clearImportedContent(noteId: UUID) {
        lastImportedContent.removeValue(forKey: noteId)
        lastImportedTitle.removeValue(forKey: noteId)
    }

    // MARK: - Directory Management

    @discardableResult
    func ensureNotesDirectory(worktreePath: String) -> String {
        let dirPath = (worktreePath as NSString).appendingPathComponent(Self.notesDir)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        return dirPath
    }

    // MARK: - Filename Generation

    static func filename(for note: Note) -> String {
        let typePrefix = note.noteType.rawValue
        let slug = SlugGenerator.generate(from: note.title)
        let base = slug.isEmpty ? "untitled" : slug
        return "\(typePrefix)--\(base).md"
    }

    // MARK: - Frontmatter Rendering

    static func renderMarkdown(for note: Note) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(note.id.uuidString)")
        lines.append("type: \(note.noteType.rawValue)")
        lines.append("title: \(yamlEscape(note.title))")
        lines.append("pinned: \(note.isPinned)")
        lines.append("created: \(formatter.string(from: note.createdAt))")
        lines.append("updated: \(formatter.string(from: note.updatedAt))")
        lines.append("---")
        lines.append("")
        lines.append(note.content)
        // Ensure file ends with newline
        if !note.content.hasSuffix("\n") {
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Frontmatter Parsing

    static func parseFrontmatter(from content: String) -> [String: Any]? {
        guard content.hasPrefix("---") else { return nil }

        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        // Find closing ---
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return nil }

        let yamlString = lines[1..<end].joined(separator: "\n")
        guard let parsed = try? Yams.load(yaml: yamlString) as? [String: Any] else { return nil }
        return parsed
    }

    static func extractBody(from content: String) -> String {
        guard content.hasPrefix("---") else { return content }

        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 2 else { return content }

        // Find closing ---
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return content }

        // Body starts after the closing --- and optional blank line
        let bodyStart = end + 1
        if bodyStart >= lines.count { return "" }

        let bodyLines = Array(lines[bodyStart...])
        var body = bodyLines.joined(separator: "\n")

        // Trim leading/trailing whitespace but preserve internal formatting
        if body.hasPrefix("\n") {
            body = String(body.dropFirst())
        }
        if body.hasSuffix("\n") {
            body = String(body.dropLast())
        }

        return body
    }

    // MARK: - CLAUDE.md Notes Section

    /// Merge a notes section into the worktree's CLAUDE.md so Claude Code knows how to interact with notes.
    static func ensureClaudeMdNotesSection(worktreePath: String) {
        let claudeMdPath = (worktreePath as NSString).appendingPathComponent("CLAUDE.md")
        let marker = "<!-- erdos-notes -->"

        var existing = (try? String(contentsOfFile: claudeMdPath, encoding: .utf8)) ?? ""

        // Don't duplicate if already present
        if existing.contains(marker) { return }

        let section = """

        \(marker)
        ## Experiment Notes

        Notes are synced as markdown files in `.erdos/notes/`. Each file has YAML frontmatter with `id`, `type`, `title`, `pinned`, `created`, and `updated` fields.

        **Reading notes:** Use `@.erdos/notes/` to reference note files, or read them directly.

        **Creating a note:** Create a new `.md` file in `.erdos/notes/` with this format:
        ```
        ---
        id: <generate-a-new-UUID>
        type: general|hypothesis|observation|decision|blocker
        title: Your Note Title
        pinned: false
        created: <ISO8601 timestamp>
        updated: <ISO8601 timestamp>
        ---

        Your note content in markdown here.
        ```

        **Editing a note:** Edit the file content or frontmatter. Erdos will sync changes back. Keep the `id` field unchanged.

        **Note types:** `general`, `hypothesis`, `observation`, `decision`, `blocker`
        """

        if !existing.isEmpty && !existing.hasSuffix("\n") {
            existing += "\n"
        }
        existing += section + "\n"

        try? existing.write(toFile: claudeMdPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func removeOldFile(for note: Note, in dirPath: String, currentFilename: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        for file in files where file.hasSuffix(".md") && file != currentFilename {
            let fullPath = (dirPath as NSString).appendingPathComponent(file)
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8),
               let frontmatter = Self.parseFrontmatter(from: content),
               let idString = frontmatter["id"] as? String,
               UUID(uuidString: idString) == note.id {
                try? fm.removeItem(atPath: fullPath)
            }
        }
    }

    private static func titleFromFilename(_ filename: String) -> String {
        // "decision--use-sse-for-streaming.md" → "use sse for streaming"
        var name = filename.replacingOccurrences(of: ".md", with: "")
        if let range = name.range(of: "--") {
            name = String(name[range.upperBound...])
        }
        return name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let date = value as? Date { return date }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }
        return nil
    }

    private static func fileModificationDate(_ path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    private static func yamlEscape(_ string: String) -> String {
        // Wrap in quotes if the string contains characters that need escaping
        if string.contains(":") || string.contains("#") || string.contains("'") ||
           string.contains("\"") || string.contains("\n") || string.hasPrefix(" ") ||
           string.hasSuffix(" ") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return string
    }
}
