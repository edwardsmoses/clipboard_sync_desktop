import Foundation

enum PairingCode {
    static func displayString(for token: String) -> String {
        let cleaned = token.uppercased()
        guard !cleaned.isEmpty else { return "" }
        var groups: [String] = []
        var current = ""
        for character in cleaned {
            current.append(character)
            if current.count == 4 {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups.joined(separator: "-")
    }
}
