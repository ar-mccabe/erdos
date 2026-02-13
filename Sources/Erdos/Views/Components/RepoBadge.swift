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

    // Greens & blues weighted heavily, browns as fallback.
    // 5 greens + 4 blues + 2 browns = 82% chance of green/blue.
    static let repoColors: [Color] = [
        // Greens
        Color(red: 0.40, green: 0.72, blue: 0.45),  // fern
        Color(red: 0.55, green: 0.78, blue: 0.52),  // sage
        Color(red: 0.35, green: 0.62, blue: 0.40),  // forest
        Color(red: 0.48, green: 0.68, blue: 0.48),  // moss
        Color(red: 0.42, green: 0.75, blue: 0.58),  // jade
        // Blues
        Color(red: 0.40, green: 0.60, blue: 0.82),  // steel blue
        Color(red: 0.50, green: 0.70, blue: 0.88),  // sky
        Color(red: 0.35, green: 0.50, blue: 0.72),  // slate
        Color(red: 0.45, green: 0.62, blue: 0.78),  // denim
        // Browns
        Color(red: 0.72, green: 0.55, blue: 0.35),  // copper
        Color(red: 0.65, green: 0.48, blue: 0.32),  // walnut
    ]
}
