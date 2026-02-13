import Foundation

enum TokenFormatter {
    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let k = Double(count) / 1_000
            return String(format: "%.1fK", k)
        default:
            let m = Double(count) / 1_000_000
            return String(format: "%.1fM", m)
        }
    }
}
