import Foundation
import SwiftData

enum TaskUpdateType: String, Codable {
    case original
    case update
}

@Model
final class TaskUpdate {
    var id: UUID
    var title: String
    var body: String
    var updateTypeRaw: String
    var costUSD: Double
    var createdAt: Date
    var experiment: Experiment?

    var updateType: TaskUpdateType {
        get { TaskUpdateType(rawValue: updateTypeRaw) ?? .original }
        set { updateTypeRaw = newValue.rawValue }
    }

    init(
        title: String,
        body: String,
        updateType: TaskUpdateType = .original,
        costUSD: Double = 0
    ) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.updateTypeRaw = updateType.rawValue
        self.costUSD = costUSD
        self.createdAt = Date()
    }
}
