import SwiftUI

struct PullRequestsView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState

    @State private var pullRequests: [GitHubPullRequest] = []
    @State private var selectedPR: GitHubPullRequest?
    @State private var prDetail: GitHubPRDetail?
    @State private var isLoading = false
    @State private var isLoadingDetail = false
    @State private var error: GitHubError?
    @State private var ghAvailable = true

    private var workingPath: String? {
        experiment.worktreePath ?? (experiment.repoPath.isEmpty ? nil : experiment.repoPath)
    }

    var body: some View {
        Group {
            if experiment.branchName == nil && experiment.worktreePath == nil {
                noBranchState
            } else if !ghAvailable {
                ghUnavailableState
            } else if pullRequests.isEmpty && !isLoading && error == nil {
                noPRsState
            } else {
                prContent
            }
        }
        .task { await loadPRs() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var prContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                prList
                    .frame(minWidth: 220, idealWidth: 280)
                prDetailView
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            let openCount = pullRequests.filter { $0.state == .open }.count
            let mergedCount = pullRequests.filter { $0.state == .merged }.count

            if openCount > 0 {
                Label("\(openCount) open", systemImage: "arrow.triangle.pull")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if mergedCount > 0 {
                Label("\(mergedCount) merged", systemImage: "arrow.triangle.merge")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            if isLoading || isLoadingDetail {
                ProgressView()
                    .controlSize(.small)
            }

            if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            if let selectedPR, let url = URL(string: selectedPR.url) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Button("Refresh") {
                Task { await loadPRs() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - PR List

    @ViewBuilder
    private var prList: some View {
        List(selection: $selectedPR) {
            let open = pullRequests.filter { $0.state == .open }
            let closed = pullRequests.filter { $0.state != .open }

            if !open.isEmpty {
                Section("Open") {
                    ForEach(open) { pr in
                        prRow(pr).tag(pr)
                    }
                }
            }

            if !closed.isEmpty {
                Section("Closed & Merged") {
                    ForEach(closed) { pr in
                        prRow(pr).tag(pr)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPR) { _, newValue in
            Task { await loadDetail(for: newValue) }
        }
    }

    @ViewBuilder
    private func prRow(_ pr: GitHubPullRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: pr.state.icon)
                    .font(.caption)
                    .foregroundStyle(prStateColor(pr.state))

                Text("#\(pr.number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                if pr.isDraft {
                    Text("Draft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(pr.title)
                .font(.caption)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(pr.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pr.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - PR Detail

    @ViewBuilder
    private var prDetailView: some View {
        if let detail = prDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    prHeader(detail)
                    prBody(detail)
                    prTimeline(detail)
                }
                .padding()
            }
        } else if isLoadingDetail {
            ProgressView("Loading PR details...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Select a Pull Request", systemImage: "text.bubble")
            } description: {
                Text("Choose a PR from the list to view its details.")
            }
        }
    }

    @ViewBuilder
    private func prHeader(_ detail: GitHubPRDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        // State badge
                        HStack(spacing: 4) {
                            Image(systemName: detail.state.icon)
                            Text(detail.state.label)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(prStateColor(detail.state).opacity(0.15))
                        .foregroundStyle(prStateColor(detail.state))
                        .clipShape(Capsule())

                        if detail.isDraft {
                            Text("Draft")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }

                        // Review decision
                        if !detail.reviewDecision.isEmpty {
                            Text(formatReviewDecision(detail.reviewDecision))
                                .font(.caption)
                                .foregroundStyle(reviewDecisionColor(detail.reviewDecision))
                        }
                    }
                }

                Spacer()
            }

            // Stats
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("+\(detail.additions)")
                        .foregroundStyle(.green)
                    Text("-\(detail.deletions)")
                        .foregroundStyle(.red)
                }
                .font(.system(.caption, design: .monospaced))

                Label("\(detail.changedFiles) files", systemImage: "doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(detail.baseRefName) \u{2190} \(detail.headRefName)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Labels
            if !detail.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(detail.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func prBody(_ detail: GitHubPRDetail) -> some View {
        if !detail.body.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                MarkdownContentView(content: detail.body, dynamicHeight: true)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func prTimeline(_ detail: GitHubPRDetail) -> some View {
        let items = buildTimeline(detail)

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity (\(items.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        switch item {
                        case .comment(let comment):
                            PRCommentCard(
                                author: comment.author,
                                body: comment.body,
                                createdAt: comment.createdAt,
                                isAuthor: comment.author == detail.author
                            )
                        case .review(let review):
                            PRReviewCard(review: review, prAuthor: detail.author)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var noBranchState: some View {
        ContentUnavailableView {
            Label("No Branch", systemImage: "arrow.triangle.branch")
        } description: {
            Text("This experiment doesn't have a branch yet. Create a worktree to associate a branch.")
        }
    }

    @ViewBuilder
    private var ghUnavailableState: some View {
        ContentUnavailableView {
            Label("GitHub CLI Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            if case .ghNotInstalled = error {
                Text("Install the GitHub CLI to view pull requests.\n\nbrew install gh")
            } else if case .notAuthenticated = error {
                Text("Authenticate with GitHub to view pull requests.\n\ngh auth login")
            } else {
                Text("The GitHub CLI (gh) is required to view pull requests.")
            }
        }
    }

    @ViewBuilder
    private var noPRsState: some View {
        ContentUnavailableView {
            Label("No Pull Requests", systemImage: "text.bubble")
        } description: {
            if let branch = experiment.branchName {
                Text("No pull requests found for branch '\(branch)'.")
            } else {
                Text("No pull requests found for this experiment.")
            }
        } actions: {
            Button("Refresh") {
                Task { await loadPRs() }
            }
        }
    }

    // MARK: - Data Loading

    private func loadPRs() async {
        guard let path = workingPath else { return }

        isLoading = true
        error = nil

        do {
            try await appState.gitHubService.checkAvailability()
            ghAvailable = true

            let prs = try await appState.gitHubService.listPRs(
                repoPath: path,
                branch: experiment.branchName
            )
            pullRequests = prs

            // Auto-select first open PR, or first PR
            if selectedPR == nil {
                selectedPR = prs.first(where: { $0.state == .open }) ?? prs.first
            }
        } catch let ghError as GitHubError {
            error = ghError
            if case .ghNotInstalled = ghError { ghAvailable = false }
            if case .notAuthenticated = ghError { ghAvailable = false }
        } catch {
            self.error = .commandFailed(error.localizedDescription)
        }

        isLoading = false
    }

    private func loadDetail(for pr: GitHubPullRequest?) async {
        guard let pr, let path = workingPath else {
            prDetail = nil
            return
        }

        isLoadingDetail = true
        do {
            prDetail = try await appState.gitHubService.getPRDetail(repoPath: path, prNumber: pr.number)
        } catch {
            prDetail = nil
        }
        isLoadingDetail = false
    }

    // MARK: - Helpers

    private func buildTimeline(_ detail: GitHubPRDetail) -> [PRTimelineItem] {
        var items: [PRTimelineItem] = []
        items += detail.comments.map { .comment($0) }
        // Filter out empty-body COMMENTED reviews with no inline comments (noise)
        items += detail.reviews
            .filter { review in
                review.state != .commented || !review.body.isEmpty || !review.comments.isEmpty
            }
            .map { .review($0) }
        return items.sorted { $0.date < $1.date }
    }

    private func prStateColor(_ state: GitHubPullRequest.PRState) -> Color {
        switch state {
        case .open: .green
        case .closed: .red
        case .merged: .purple
        }
    }

    private func formatReviewDecision(_ decision: String) -> String {
        switch decision {
        case "APPROVED": "Approved"
        case "CHANGES_REQUESTED": "Changes Requested"
        case "REVIEW_REQUIRED": "Review Required"
        default: decision.capitalized
        }
    }

    private func reviewDecisionColor(_ decision: String) -> Color {
        switch decision {
        case "APPROVED": .green
        case "CHANGES_REQUESTED": .orange
        case "REVIEW_REQUIRED": .secondary
        default: .secondary
        }
    }
}
