import Foundation
import Testing
@testable import RawCull

@MainActor
struct KeyBindingStoreTests {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suiteName = "RawCullTests.KeyBindings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try test(defaults)
    }

    @Test func defaultsMatchEveryRequiredPhysicalKeyInOrder() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            let expected: [CullAction: [UInt16]] = [
                .previous: [123, 126, 4], .next: [124, 125, 37],
                .pick: [0], .unmark: [1], .reject: [2],
                .rotateCounterClockwise: [6], .resetView: [7], .rotateClockwise: [8],
                .zoom: [49], .saveRotation: [36, 76],
                .toggleThumbnails: [17], .toggleFolderTree: [3]
            ]
            #expect(store.bindings.mapValues { $0.map(\.keyCode) } == expected)
            #expect(Set(expected.keys) == Set(CullAction.allCases))
            #expect(store.keys(for: .previous).map(\.label) == ["←", "↑", "H"])
            #expect(store.keys(for: .next).map(\.label) == ["→", "↓", "L"])
            #expect(store.keys(for: .saveRotation).map(\.label) == ["Return", "Enter"])
        }
    }

    @Test func lookupFindsEveryDefaultAndLeavesUnboundKeysAlone() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            for (action, keys) in store.bindings {
                for key in keys {
                    #expect(store.action(for: key.keyCode) == action)
                }
            }
            #expect(store.action(for: 12) == nil) // Q
            #expect(store.action(for: 53) == nil) // Escape
            #expect(store.action(for: UInt16.max) == nil)
        }
    }

    @Test func roundTripRetainsMultipleBindingsOrderAndEmptyActions() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            store.remove(keyCode: 0, from: .pick)
            store.add(keyCode: 12, to: .pick)
            store.add(keyCode: 13, to: .pick)
            store.remove(keyCode: 2, from: .reject)
            store.beginRecording(for: .zoom)

            let restored = KeyBindingStore(defaults: defaults)
            #expect(restored.bindings == store.bindings)
            #expect(restored.keys(for: .pick).map(\.label) == ["Q", "W"])
            #expect(restored.keys(for: .reject).isEmpty)
            #expect(restored.action(for: 0) == nil)
            #expect(restored.action(for: 12) == .pick)
            #expect(!restored.isRecording)
        }
    }

    @Test(arguments: [Data("not JSON".utf8), Data("{}".utf8), Data("[]".utf8), Data("null".utf8)])
    func corruptOrIncompleteStoredDataFallsBackToDefaults(data: Data) throws {
        try withDefaults { defaults in
            defaults.set(data, forKey: KeyBindingStore.storageKey)
            #expect(KeyBindingStore(defaults: defaults).bindings == KeyBindingStore.defaultBindings)
        }
    }

    @Test func duplicateOrUnsupportedStoredKeysFallBackToDefaults() throws {
        try withDefaults { defaults in
            var bindings = KeyBindingStore.defaultBindings
            bindings[.reject] = bindings[.pick]
            defaults.set(try JSONEncoder().encode(bindings), forKey: KeyBindingStore.storageKey)
            #expect(KeyBindingStore(defaults: defaults).bindings == KeyBindingStore.defaultBindings)

            let escape = try JSONDecoder().decode(KeyBinding.self, from: Data(#"{"keyCode":53,"label":"Escape"}"#.utf8))
            bindings = KeyBindingStore.defaultBindings
            bindings[.pick] = [escape]
            defaults.set(try JSONEncoder().encode(bindings), forKey: KeyBindingStore.storageKey)
            #expect(KeyBindingStore(defaults: defaults).bindings == KeyBindingStore.defaultBindings)
        }
    }

    @Test func persistedLabelsAreCanonicalizedFromPhysicalKeys() throws {
        try withDefaults { defaults in
            var bindings = KeyBindingStore.defaultBindings
            let koreanLabel = try JSONDecoder().decode(KeyBinding.self, from: Data(#"{"keyCode":0,"label":"ㅁ"}"#.utf8))
            bindings[.pick] = [koreanLabel]
            defaults.set(try JSONEncoder().encode(bindings), forKey: KeyBindingStore.storageKey)
            let store = KeyBindingStore(defaults: defaults)
            #expect(store.keys(for: .pick).first?.label == "A")
            #expect(store.action(for: 0) == .pick)
        }
    }

    @Test func conflictMovesKeyAndCanLeavePreviousActionEmpty() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            #expect(store.add(keyCode: 2, to: .pick) == .reject)
            #expect(store.keys(for: .reject).isEmpty)
            #expect(store.keys(for: .pick).map(\.keyCode) == [0, 2])
            #expect(store.action(for: 2) == .pick)
            #expect(KeyBindingStore(defaults: defaults).bindings == store.bindings)

            #expect(store.add(keyCode: 123, to: .zoom) == .previous)
            #expect(store.keys(for: .previous).map(\.keyCode) == [126, 4])
            #expect(store.keys(for: .zoom).map(\.keyCode) == [49, 123])
        }
    }

    @Test func addingSameKeyTwicePreservesOrderWithoutDuplicates() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            #expect(store.add(keyCode: 12, to: .pick) == nil)
            #expect(store.add(keyCode: 0, to: .pick) == nil)
            #expect(store.add(keyCode: 12, to: .pick) == nil)
            #expect(store.keys(for: .pick).map(\.keyCode) == [0, 12])
        }
    }

    @Test func removingFirstKeyPromotesNextAndLastRemovalUnbindsAction() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            store.remove(keyCode: 36, from: .saveRotation)
            #expect(store.keys(for: .saveRotation).first?.label == "Enter")
            #expect(store.action(for: 36) == nil)
            store.remove(keyCode: 76, from: .saveRotation)
            #expect(store.keys(for: .saveRotation).isEmpty)
            #expect(store.action(for: 76) == nil)
            #expect(KeyBindingStore(defaults: defaults).keys(for: .saveRotation).isEmpty)
        }
    }

    @Test func unsupportedKeysCannotBeAssigned() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            for code: UInt16 in [53, 56, UInt16.max] { // Escape, Shift, unknown
                #expect(store.add(keyCode: code, to: .pick) == nil)
            }
            #expect(store.bindings == KeyBindingStore.defaultBindings)
            #expect(defaults.data(forKey: KeyBindingStore.storageKey) == nil)
        }
    }

    @Test func restoreDefaultsPersistsAndCancelsRecording() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            store.add(keyCode: 0, to: .reject)
            store.remove(keyCode: 49, from: .zoom)
            store.beginRecording(for: .pick)
            #expect(store.isRecording)

            store.restoreDefaults()

            #expect(!store.isRecording)
            #expect(store.bindings == KeyBindingStore.defaultBindings)
            #expect(KeyBindingStore(defaults: defaults).bindings == KeyBindingStore.defaultBindings)
        }
    }

    @Test func recordingCanSwitchActionsAndCancelWithoutChangingBindings() throws {
        try withDefaults { defaults in
            let store = KeyBindingStore(defaults: defaults)
            store.beginRecording(for: .pick)
            #expect(store.recordingAction == .pick)
            store.beginRecording(for: .reject)
            #expect(store.recordingAction == .reject)
            store.cancelRecording()
            #expect(!store.isRecording)
            #expect(store.bindings == KeyBindingStore.defaultBindings)
            #expect(defaults.data(forKey: KeyBindingStore.storageKey) == nil)
        }
    }

    @Test func ansiTableIncludesLettersDigitsPunctuationSpecialKeysAndFunctionKeys() {
        let labels = Set(KeyBinding.labels.values)
        #expect(Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)).isSubset(of: labels))
        #expect(Set("0123456789".map(String.init)).isSubset(of: labels))
        #expect(Set("`-=[]\\;',./".map(String.init)).isSubset(of: labels))
        #expect(Set(["←", "↑", "→", "↓", "Space", "Return", "Enter", "Tab", "Delete"]).isSubset(of: labels))
        #expect(Set((1...12).map { "F\($0)" }).isSubset(of: labels))
        #expect(KeyBinding(keyCode: 53) == nil)
    }
}
