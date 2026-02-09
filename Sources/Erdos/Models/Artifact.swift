import Foundation
import SwiftData

enum ArtifactType: String, Codable, CaseIterable, Identifiable {
    case plan
    case code
    case config
    case doc
    case test
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plan: "Plan"
        case .code: "Code"
        case .config: "Config"
        case .doc: "Doc"
        case .test: "Test"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .plan: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .config: "gearshape"
        case .doc: "doc.richtext"
        case .test: "checkmark.rectangle"
        case .other: "doc"
        }
    }

    static func infer(from filename: String) -> ArtifactType {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let name = URL(fileURLWithPath: filename).lastPathComponent.lowercased()

        if name.contains("plan") || name == "claude.md" { return .plan }
        if name.hasPrefix("test") || name.hasSuffix("_test") || name.contains(".test.") || name.contains(".spec.") { return .test }
        if ["json", "yaml", "yml", "toml", "ini", "env"].contains(ext) { return .config }
        if ["md", "txt", "rst", "adoc"].contains(ext) { return .doc }
        if ["py", "swift", "ts", "tsx", "js", "jsx", "rs", "go", "rb", "java", "kt", "c", "cpp", "h"].contains(ext) { return .code }
        return .other
    }
}

@Model
final class Artifact {
    var id: UUID
    var filePath: String
    var artifactTypeRaw: String
    var label: String?
    var autoDiscovered: Bool
    var createdAt: Date
    var experiment: Experiment?

    var artifactType: ArtifactType {
        get { ArtifactType(rawValue: artifactTypeRaw) ?? .other }
        set { artifactTypeRaw = newValue.rawValue }
    }

    init(
        filePath: String,
        artifactType: ArtifactType? = nil,
        label: String? = nil,
        autoDiscovered: Bool = false
    ) {
        self.id = UUID()
        self.filePath = filePath
        self.artifactTypeRaw = (artifactType ?? ArtifactType.infer(from: filePath)).rawValue
        self.label = label
        self.autoDiscovered = autoDiscovered
        self.createdAt = Date()
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}
