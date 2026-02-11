import SwiftUI

struct PRCommentCard: View {
    let author: String
    let content: String
    let createdAt: Date
    let isAuthor: Bool

    init(author: String, body: String, createdAt: Date, isAuthor: Bool = false) {
        self.author = author
        self.content = body
        self.createdAt = createdAt
        self.isAuthor = isAuthor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                // Author initial circle
                Text(String(author.prefix(1)).uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.blue))

                Text(author)
                    .font(.caption)
                    .fontWeight(.semibold)

                if isAuthor {
                    Text("Author")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Body
            if !content.isEmpty {
                MarkdownContentView(content: content, dynamicHeight: true)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
