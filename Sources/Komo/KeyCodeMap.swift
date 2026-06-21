import Foundation

/// Maps ANSI virtual key codes to printable labels and provides the
/// visual keyboard layout used by the heat-map. Virtual key codes are
/// physical positions, so counts stay consistent across keyboard layouts.
///
/// Both the main number row and the numeric keypad map onto the same digit
/// labels, and only labels present in this map are counted.
enum KeyCodeMap {
    static let labels: [UInt16: String] = [
        // Letters
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        // Main number row
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",
        // Numeric keypad → same digit buckets
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
        87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        // Space bar
        49: "Space"
    ]

    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
    static let digits: [String] = "0123456789".map(String.init)

    /// Rows for the on-screen heat-map keyboard.
    static let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["Space"]
    ]

    /// Per-row leading offset that mimics a real keyboard's stagger.
    static let rowOffsets: [Double] = [0, 0, 16, 38, 84]
}
