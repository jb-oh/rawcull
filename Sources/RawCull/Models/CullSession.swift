import Foundation
import Observation

@MainActor
@Observable
final class CullSession {
    private(set) var items: [PhotoItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var selectedItemIDs: Set<PhotoItem.ID> = []
    private(set) var selectionAnchorIndex: Int = 0
    var isLoaded: Bool = false
    private(set) var pickCount: Int = 0
    private(set) var rejectCount: Int = 0
    private(set) var undecidedCount: Int = 0

    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasPendingSave = false
    @ObservationIgnored
    private let writeSession: (SavedSession, URL) throws -> Void
    private(set) var folderURL: URL?

    init(writeSession: @escaping (SavedSession, URL) throws -> Void = { saved, url in
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }) {
        self.writeSession = writeSession
    }

    // MARK: - Navigation

    var currentItem: PhotoItem? {
        guard !items.isEmpty, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var count: Int { items.count }

    func next() {
        jumpTo(index: min(currentIndex + 1, items.count - 1))
    }

    func previous() {
        jumpTo(index: max(0, currentIndex - 1))
    }

    func jumpTo(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        collapseSelection()
    }

    // MARK: - Selection

    var selectionCount: Int { selectedItemIDs.count }

    var actionTargets: [PhotoItem] {
        if selectionCount > 1 {
            return items.filter { selectedItemIDs.contains($0.id) }
        }
        return currentItem.map { [$0] } ?? []
    }

    func isSelected(index: Int) -> Bool {
        items.indices.contains(index) && selectedItemIDs.contains(items[index].id)
    }

    func select(index: Int, extendingRange: Bool = false, toggling: Bool = false) {
        guard items.indices.contains(index) else { return }
        if extendingRange {
            let range = min(selectionAnchorIndex, index)...max(selectionAnchorIndex, index)
            selectedItemIDs = Set(range.map { items[$0].id })
            currentIndex = index
        } else if toggling {
            let id = items[index].id
            if selectedItemIDs.contains(id) {
                guard selectionCount > 1 else { return }
                selectedItemIDs.remove(id)
                if currentIndex == index {
                    // Ascending indices keep the lower index when distances tie.
                    currentIndex = items.indices.filter { isSelected(index: $0) }.min {
                        abs($0 - index) < abs($1 - index)
                    }!
                }
            } else {
                selectedItemIDs.insert(id)
                currentIndex = index
            }
            selectionAnchorIndex = currentIndex
        } else {
            jumpTo(index: index)
        }
    }

    /// Returns whether Escape should be consumed.
    @discardableResult
    func collapseSelection() -> Bool {
        let hadMultipleSelection = selectionCount > 1
        selectedItemIDs = Set(currentItem.map { [$0.id] } ?? [])
        selectionAnchorIndex = currentIndex
        return hadMultipleSelection
    }

    func contextMenuTargets(index: Int) -> [PhotoItem] {
        guard items.indices.contains(index) else { return [] }
        return selectionCount > 1 && isSelected(index: index) ? actionTargets : [items[index]]
    }

    // MARK: - Decisions

    func markPick() {
        applyDecision(.pick, to: actionTargets.map(\.id))
    }

    func markReject() {
        applyDecision(.reject, to: actionTargets.map(\.id))
    }

    func unmarkCurrent() {
        applyDecision(.undecided, to: actionTargets.map(\.id))
    }

    func applyDecision(_ newDecision: Decision, to targetIDs: [PhotoItem.ID]) {
        let targets = Set(targetIDs)
        var changed = false
        for index in items.indices where targets.contains(items[index].id) {
            let oldDecision = items[index].decision
            guard oldDecision != newDecision else { continue }
            updateCounts(from: oldDecision, to: newDecision)
            items[index].decision = newDecision
            changed = true
        }
        if changed { scheduleSave() }
    }

    // MARK: - Session Loading

    func load(folderURL: URL, fileURLs: [URL]) {
        flushSave()
        self.folderURL = folderURL

        let saved = SavedSession.load(from: folderURL)
        let defaultDecision = SortedFolder(folderURL: folderURL)?.decision ?? .undecided
        self.items = fileURLs.map { url in
            let decision = saved?.decisions[url.lastPathComponent] ?? defaultDecision
            return PhotoItem(url: url, decision: decision)
        }
        self.currentIndex = max(0, min(saved?.currentIndex ?? 0, fileURLs.count - 1))
        collapseSelection()

        rebuildCounts()
        self.isLoaded = true
    }

    func reset() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        items = []
        currentIndex = 0
        collapseSelection()
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

    /// Drops any pending debounced save without deleting the session file.
    func discardPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
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
        let sessionURL = SavedSession.url(in: folderURL)
        var decisions: [String: Decision] = [:]
        for item in items {
            decisions[item.filename] = item.decision
        }
        let saved = SavedSession(
            version: 1,
            currentIndex: currentIndex,
            decisions: decisions
        )
        if (try? writeSession(saved, sessionURL)) != nil {
            hasPendingSave = false
        }
    }

    func deleteSessionFile() {
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        guard let folderURL else { return }
        let sessionURL = SavedSession.url(in: folderURL)
        try? FileManager.default.removeItem(at: sessionURL)
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
