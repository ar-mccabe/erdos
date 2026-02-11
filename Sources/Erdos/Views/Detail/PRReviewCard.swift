import SwiftUI

struct PRReviewCard: View {
    let review: GitHubReview
    let prAuthor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: review.state.icon)
                    .foregroundStyle(stateColor)
                    .font(.caption)

                Text(String(review.author.prefix(1)).uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(stateColor))

                Text(review.author)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(review.state.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.15))
                    .foregroundStyle(stateColor)
                    .clipShape(Capsule())

                if review.author == prAuthor {
                    Text("Author")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(review.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Review body
            if !review.body.isEmpty {
                MarkdownContentView(content: review.body, dynamicHeight: true)
            }

            // Inline comments
            if !review.comments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(review.comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(comment.path)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let line = comment.line {
                                    Text("L\(line)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if !comment.body.isEmpty {
                                MarkdownContentView(content: comment.body, dynamicHeight: true)
                            }
                        }
                        .padding(8)
                        .background(.background.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(stateColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var stateColor: Color {
        switch review.state {
        case .approved: .green
        case .changesRequested: .orange
        case .commented: .blue
        case .dismissed: .gray
        case .pending: .secondary
        }
    }
}
