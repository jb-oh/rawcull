import Foundation

enum Decision: String, Codable {
    case undecided
    case pick
    case reject
}

struct PhotoItem: Identifiable {
    let id: UUID
    let url: URL
    var decision: Decision

    var filename: String {
        url.lastPathComponent
    }

    init(url: URL, decision: Decision = .undecided) {
        self.id = UUID()
        self.url = url
        self.decision = decision
    }
}
