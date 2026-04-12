import Foundation

struct TerminalTab: Identifiable {
    let id = UUID()
    var label: String
    var initialCommand: String?
    var delayedInput: String?

    var isClaudeTab: Bool {
        label.localizedCaseInsensitiveContains("claude")
            || (initialCommand?.localizedCaseInsensitiveContains("claude") ?? false)
    }
}
