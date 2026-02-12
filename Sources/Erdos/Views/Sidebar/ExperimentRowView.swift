import SwiftUI

struct ExperimentRowView: View {
    let experiment: Experiment
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(experiment.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if appState.experimentsWaitingForInput.contains(experiment.id) {
                    Circle()
                        .fill(ErdosColors.attentionDot)
                        .frame(width: 8, height: 8)
                }
                Spacer()
                if !experiment.repoPath.isEmpty {
                    RepoBadge(name: experiment.repoName)
                }
            }
            if !experiment.hypothesis.isEmpty {
                Text(experiment.hypothesis)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
