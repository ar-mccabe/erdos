import SwiftUI
import AppKit

struct CopyableLabel: View {
    let text: String
    var icon: String? = nil
    var display: String? = nil
    var font: Font = .caption
    var color: HierarchicalShapeStyle = .secondary

    @State private var showCopied = false

    var body: some View {
        Group {
            if showCopied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else if let icon {
                Label(display ?? text, systemImage: icon)
                    .foregroundStyle(color)
            } else {
                Text(display ?? text)
                    .foregroundStyle(color)
            }
        }
        .font(font)
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
            }
        }
        .help("Click to copy")
        .cursor(.pointingHand)
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
