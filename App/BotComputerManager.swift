import Foundation

@MainActor
final class BotComputerManager: ObservableObject {
    @Published private(set) var computers: [BotComputerRecord] = []

    private let service: BotComputerService
    /// Tail of the reload chain.
    private var workTask: Task<Void, Never>?

    init(service: BotComputerService = .shared) {
        self.service = service
    }

    /// Queued, not dropped: each reload waits for the one before it, so the newest state lands last.
    func reload() {
        let previous = workTask
        workTask = Task { [weak self, service] in
            await previous?.value
            guard let records = try? await service.refresh() else { return }
            self?.computers = records
        }
    }
}
