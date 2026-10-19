import Foundation
import Observation

@MainActor
@Observable
final class KeyBindingStore {
    static let storageKey = "cullingKeyBindings"

    static let defaultBindings: [CullAction: [KeyBinding]] = {
        let codes: [CullAction: [UInt16]] = [
            .previous: [123, 126, 4],
            .next: [124, 125, 37],
            .pick: [0],
            .unmark: [1],
            .reject: [2],
            .rotateCounterClockwise: [6],
            .resetView: [7],
            .rotateClockwise: [8],
            .zoom: [49],
            .saveRotation: [36, 76],
            .toggleThumbnails: [17],
            .toggleFolderTree: [3]
        ]
        return codes.mapValues { $0.compactMap { KeyBinding(keyCode: $0) } }
    }()

    private(set) var bindings: [CullAction: [KeyBinding]]
    private(set) var recordingAction: CullAction?
    @ObservationIgnored private let defaults: UserDefaults

    var isRecording: Bool { recordingAction != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([CullAction: [KeyBinding]].self, from: data),
           let validated = Self.validated(decoded) {
            bindings = validated
        } else {
            bindings = Self.defaultBindings
        }
    }

    func keys(for action: CullAction) -> [KeyBinding] {
        bindings[action] ?? []
    }

    func action(for keyCode: UInt16) -> CullAction? {
        CullAction.allCases.first { keys(for: $0).contains { $0.keyCode == keyCode } }
    }

    /// A key has one owner. Adding it to another action moves it, preserving key order.
    @discardableResult
    func add(keyCode: UInt16, to action: CullAction) -> CullAction? {
        guard let key = KeyBinding(keyCode: keyCode) else { return nil }
        let previous = self.action(for: keyCode)
        guard previous != action else { return nil }
        if let previous {
            bindings[previous]?.removeAll { $0.keyCode == keyCode }
        }
        bindings[action, default: []].append(key)
        persist()
        return previous
    }

    func remove(keyCode: UInt16, from action: CullAction) {
        bindings[action]?.removeAll { $0.keyCode == keyCode }
        persist()
    }

    func restoreDefaults() {
        cancelRecording()
        bindings = Self.defaultBindings
        persist()
    }

    func beginRecording(for action: CullAction) {
        recordingAction = action
    }

    func cancelRecording() {
        recordingAction = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func validated(_ decoded: [CullAction: [KeyBinding]]) -> [CullAction: [KeyBinding]]? {
        var result: [CullAction: [KeyBinding]] = [:]
        var seen: Set<UInt16> = []
        for action in CullAction.allCases {
            guard let keys = decoded[action] else { return nil }
            result[action] = []
            for stored in keys {
                guard let key = KeyBinding(keyCode: stored.keyCode), seen.insert(key.keyCode).inserted else {
                    return nil
                }
                // Even persisted labels come from the ANSI table, never an input source.
                result[action, default: []].append(key)
            }
        }
        return result
    }
}
