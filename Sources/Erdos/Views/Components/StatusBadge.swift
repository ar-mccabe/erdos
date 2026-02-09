import SwiftUI

struct StatusBadge: View {
    let status: ExperimentStatus

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .idea: .purple
        case .researching: .blue
        case .planned: .cyan
        case .active: .green
        case .paused: .orange
        case .completed: .gray
        case .abandoned: .red
        }
    }
}
