import Foundation

enum CullAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case previous
    case next
    case pick
    case unmark
    case reject
    case rotateCounterClockwise
    case resetView
    case rotateClockwise
    case zoom
    case saveRotation
    case toggleThumbnails
    case toggleFolderTree

    var id: Self { self }

    var displayName: String {
        switch self {
        case .previous: return String(localized: "Previous Photo", bundle: Localization.bundle)
        case .next: return String(localized: "Next Photo", bundle: Localization.bundle)
        case .pick: return String(localized: "Pick", bundle: Localization.bundle)
        case .unmark: return String(localized: "Unmark", bundle: Localization.bundle)
        case .reject: return String(localized: "Reject", bundle: Localization.bundle)
        case .rotateCounterClockwise: return String(localized: "Rotate Counterclockwise", bundle: Localization.bundle)
        case .resetView: return String(localized: "Reset View", bundle: Localization.bundle)
        case .rotateClockwise: return String(localized: "Rotate Clockwise", bundle: Localization.bundle)
        case .zoom: return String(localized: "Zoom", bundle: Localization.bundle)
        case .saveRotation: return String(localized: "Save Rotation", bundle: Localization.bundle)
        case .toggleThumbnails: return String(localized: "Toggle Thumbnails", bundle: Localization.bundle)
        case .toggleFolderTree: return String(localized: "Toggle Folder Tree", bundle: Localization.bundle)
        }
    }
}

struct KeyBinding: Codable, Equatable, Identifiable, Sendable {
    let keyCode: UInt16
    let label: String

    var id: UInt16 { keyCode }

    init?(keyCode: UInt16) {
        guard let label = Self.labels[keyCode] else { return nil }
        self.keyCode = keyCode
        self.label = label
    }

    /// Physical ANSI keys, independent of the active input source. Escape cancels recording.
    static let labels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 76: "Enter", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        117: "Forward Delete", 118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
