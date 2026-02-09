import SwiftUI

struct ExperimentRowView: View {
    let experiment: Experiment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(experiment.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: experiment.status)
            }
            if !experiment.hypothesis.isEmpty {
                Text(experiment.hypothesis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !experiment.repoPath.isEmpty {
                Text(experiment.repoName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
