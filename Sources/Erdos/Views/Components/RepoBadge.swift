import SwiftUI

struct RepoBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .foregroundStyle(color.opacity(0.8))
    }

    var color: Color {
        Self.repoColors[Self.stableIndex(for: name)]
    }

    private static func stableIndex(for string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(repoColors.count))
    }

    // Warm neutrals only — no blues, teals, greens, or purples
    // that could overlap with the status gradient.
    static let repoColors: [Color] = [
        Color(red: 0.80, green: 0.52, blue: 0.35),  // terracotta
        Color(red: 0.72, green: 0.55, blue: 0.35),  // copper
        Color(red: 0.75, green: 0.62, blue: 0.44),  // sand
        Color(red: 0.65, green: 0.42, blue: 0.35),  // clay
        Color(red: 0.78, green: 0.48, blue: 0.40),  // rust
        Color(red: 0.68, green: 0.58, blue: 0.48),  // driftwood
        Color(red: 0.72, green: 0.48, blue: 0.50),  // rosewood
        Color(red: 0.62, green: 0.52, blue: 0.40),  // sienna
    ]
}
