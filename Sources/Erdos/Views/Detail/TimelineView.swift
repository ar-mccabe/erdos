import SwiftUI
import SwiftData

struct TimelineView: View {
    @Bindable var experiment: Experiment
    @Environment(\.modelContext) private var modelContext
    @State private var newEventText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add manual event
            HStack {
                TextField("Add a note to the timeline...", text: $newEventText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addManualEvent()
                    }
                Button("Add") {
                    addManualEvent()
                }
                .disabled(newEventText.isEmpty)
            }
            .padding(8)

            Divider()

            if sortedEvents.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "clock",
                    description: Text("Events are recorded automatically as you work.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedEvents) { event in
                            HStack(alignment: .top, spacing: 12) {
                                // Timeline dot and line
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(colorFor(event.eventType))
                                        .frame(width: 8, height: 8)
                                    Rectangle()
                                        .fill(.quaternary)
                                        .frame(width: 1)
                                }
                                .frame(width: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Image(systemName: event.eventType.icon)
                                            .font(.caption)
                                            .foregroundStyle(colorFor(event.eventType))
                                        Text(event.summary)
                                            .font(.body)
                                    }
                                    if let detail = event.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(event.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)

                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var sortedEvents: [TimelineEvent] {
        experiment.timeline.sorted { $0.createdAt > $1.createdAt }
    }

    private func addManualEvent() {
        guard !newEventText.isEmpty else { return }
        let event = TimelineEvent(eventType: .manual, summary: newEventText)
        event.experiment = experiment
        modelContext.insert(event)
        newEventText = ""
    }

    private func colorFor(_ type: EventType) -> Color {
        switch type {
        case .statusChange: .blue
        case .noteAdded: .purple
        case .artifactCreated: .cyan
        case .sessionStarted: .green
        case .sessionEnded: .orange
        case .branchCreated: .teal
        case .manual: .secondary
        case .autoStatusChange: .mint
        case .taskDrafted: .indigo
        case .taskUpdateDrafted: .indigo
        }
    }
}
