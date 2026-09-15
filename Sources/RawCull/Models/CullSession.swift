import Foundation
import Observation

@MainActor
@Observable
final class CullSession {
    var items: [PhotoItem] = []
    var currentIndex: Int = 0
    var isLoaded: Bool = false
    private(set) var pickCount: Int = 0
    private(set) var rejectCount: Int = 0
    private(set) var undecidedCount: Int = 0

    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasPendingSave = false
    private(set) var folderURL: URL?

    // MARK: - Navigation

    var currentItem: PhotoItem? {
        guard !items.isEmpty, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var count: Int { items.count }

    func next() {
        guard currentIndex < items.count - 1 else { return }
        currentIndex += 1
    }

    func previous() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func jumpTo(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    // MARK: - Decisions

    func markPick() {
        applyDecision(.pick)
    }

    func markReject() {
        applyDecision(.reject)
    }

    func unmarkCurrent() {
        applyDecision(.undecided)
    }

    // MARK: - Session Loading

    func load(folderURL: URL, fileURLs: [URL]) {
        flushSave()
        self.folderURL = folderURL

        // Check for existing session
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        if let data = try? Data(contentsOf: sessionURL),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data) {
            self.items = fileURLs.map { url in
                let decision = saved.decisions[url.lastPathComponent] ?? .undecided
                return PhotoItem(url: url, decision: decision)
            }
            self.currentIndex = max(0, min(saved.currentIndex, fileURLs.count - 1))
        } else {
            self.items = fileURLs.map { PhotoItem(url: $0) }
            self.currentIndex = 0
        }

        rebuildCounts()
        self.isLoaded = true
    }

    func reset() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        items = []
        currentIndex = 0
        pickCount = 0
        rejectCount = 0
        undecidedCount = 0
        folderURL = nil
        isLoaded = false
    }

    // MARK: - Persistence

    /// Writes any pending decisions to disk right away. Call before switching
    /// folders, closing the folder, or quitting, so the one second debounce
    /// in `scheduleSave()` cannot drop the last decision.
    func flushSave() {
        guard hasPendingSave else { return }
        saveTask?.cancel()
        saveTask = nil
        saveSession()
    }

    private func scheduleSave() {
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    private func saveSession() {
        guard let folderURL else { return }
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        var decisions: [String: Decision] = [:]
        for item in items {
            decisions[item.filename] = item.decision
        }
        let saved = SavedSession(
            version: 1,
            currentIndex: currentIndex,
            decisions: decisions
        )
        if let data = try? JSONEncoder().encode(saved),
           (try? data.write(to: sessionURL, options: .atomic)) != nil {
            hasPendingSave = false
        }
    }

    func deleteSessionFile() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        guard let folderURL else { return }
        let sessionURL = folderURL.appendingPathComponent(".rawcull-session.json")
        try? FileManager.default.removeItem(at: sessionURL)
    }

    private func applyDecision(_ newDecision: Decision) {
        guard let item = currentItem, item.decision != newDecision else { return }
        updateCounts(from: item.decision, to: newDecision)
        items[currentIndex].decision = newDecision
        scheduleSave()
    }

    private func rebuildCounts() {
        pickCount = 0
        rejectCount = 0
        undecidedCount = 0

        for item in items {
            switch item.decision {
            case .pick:
                pickCount += 1
            case .reject:
                rejectCount += 1
            case .undecided:
                undecidedCount += 1
            }
        }
    }

    private func updateCounts(from oldDecision: Decision, to newDecision: Decision) {
        guard oldDecision != newDecision else { return }

        switch oldDecision {
        case .pick:
            pickCount -= 1
        case .reject:
            rejectCount -= 1
        case .undecided:
            undecidedCount -= 1
        }

        switch newDecision {
        case .pick:
            pickCount += 1
        case .reject:
            rejectCount += 1
        case .undecided:
            undecidedCount += 1
        }
    }
}

// MARK: - Saved Session Format

private struct SavedSession: Codable {
    let version: Int
    let currentIndex: Int
    let decisions: [String: Decision]
}
