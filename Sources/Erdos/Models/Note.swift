import Foundation
import SwiftData

enum NoteType: String, Codable, CaseIterable, Identifiable {
    case general
    case hypothesis
    case observation
    case decision
    case blocker
    case archive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .hypothesis: "Hypothesis"
        case .observation: "Observation"
        case .decision: "Decision"
        case .blocker: "Blocker"
        case .archive: "Archive"
        }
    }

    var icon: String {
        switch self {
        case .general: "note.text"
        case .hypothesis: "lightbulb"
        case .observation: "eye"
        case .decision: "checkmark.seal"
        case .blocker: "exclamationmark.triangle"
        case .archive: "archivebox"
        }
    }
}

@Model
final class Note {
    var id: UUID
    var title: String
    var content: String
    var noteTypeRaw: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var experiment: Experiment?

    var noteType: NoteType {
        get { NoteType(rawValue: noteTypeRaw) ?? .general }
        set { noteTypeRaw = newValue.rawValue }
    }

    init(
        title: String = "Untitled",
        content: String = "",
        noteType: NoteType = .general,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.noteTypeRaw = noteType.rawValue
        self.isPinned = isPinned
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
