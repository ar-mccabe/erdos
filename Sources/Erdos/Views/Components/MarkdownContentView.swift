import SwiftUI

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(LocalizedStringKey(content))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
