import Foundation
import os

/// Conservative budgets, not model benchmarks. Read capacity afresh at each check.
struct ModelResourceGuard: Sendable {
    static let reserve: Int64 = 256 * 1_024 * 1_024
    static let maximumInputTokens = 4_096
    var availableMemory: @Sendable () -> Int64 = { Int64(os_proc_available_memory()) }
    var availableStorage: @Sendable () throws -> Int64 = {
        let values = try ModelStorage.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
            throw ModelResourceError.capacityUnavailable
        }
        return bytes
    }

    static func downloadBudget(for model: SummaryModelID) -> Int64 {
        // Retain room for the temporary download and final copy, plus app data.
        model.approximateDownloadBytes * 2 + reserve * 2
    }

    func checkDownload(_ model: SummaryModelID, reservedBytes: Int64 = 0) throws {
        let available: Int64
        do { available = try availableStorage() }
        catch { throw ModelResourceError.capacityUnavailable }
        let required = Self.downloadBudget(for: model) + reservedBytes
        guard available >= required else {
            throw ModelResourceError.storage(required: required, available: max(0, available))
        }
    }

    func checkLoad(weightBytes: Int64) throws {
        // Loading can temporarily hold both mapped weights and GPU allocations.
        try checkMemory(required: max(0, weightBytes) * 2 + Self.reserve * 3)
    }

    func checkGeneration(inputTokens: Int, outputTokens: Int) throws {
        guard inputTokens <= Self.maximumInputTokens else { throw ModelResourceError.inputTooLong }
        // Budget KV state and prefill workspace separately from resident weights.
        let tokens = Int64(max(0, inputTokens) + max(0, outputTokens))
        try checkMemory(required: Self.reserve * 3 + tokens * 160 * 1_024)
    }

    func checkMemory(required: Int64 = Self.reserve) throws {
        let available = max(0, availableMemory())
        guard available >= required else {
            throw ModelResourceError.memory(required: required, available: available)
        }
    }

    /// Poll independently of the model actor so checks continue during prefill/loading.
    /// Cancellation propagates to the worker; its partial result is never returned.
    func monitoring<Value: Sendable>(
        storage: Bool = false,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let pressure = storage ? nil : MemoryPressureObserver()
        defer { pressure?.stop() }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                while true {
                    try await Task.sleep(for: storage ? .seconds(1) : .milliseconds(200))
                    if storage {
                        let available = try availableStorage()
                        guard available >= Self.reserve else {
                            throw ModelResourceError.storage(required: Self.reserve, available: max(0, available))
                        }
                    } else {
                        if pressure?.isUnderPressure == true { throw ModelResourceError.memoryPressure }
                        try checkMemory()
                    }
                }
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

enum ModelResourceError: LocalizedError, Equatable {
    case storage(required: Int64, available: Int64)
    case memory(required: Int64, available: Int64)
    case memoryPressure
    case capacityUnavailable
    case inputTooLong
    case busy

    var errorDescription: String? {
        switch self {
        case .storage(let required, let available):
            "Not enough storage. This download needs about \(Self.size(required)) free; \(Self.size(available)) is available. Free up space or choose a smaller model in Settings."
        case .memory(let required, let available):
            "Not enough available memory for this model. About \(Self.size(required)) is needed; \(Self.size(available)) is available. Try again later or choose a smaller model in Settings. Your diary is unchanged."
        case .memoryPressure:
            "Your device is low on memory, so the model was stopped. Try again later or choose a smaller model in Settings. Your diary is unchanged."
        case .capacityUnavailable:
            "Available storage could not be checked. Please try the download again."
        case .inputTooLong:
            "This entry is too long to summarise safely on this device. Try a shorter entry or a shorter date range for insights."
        case .busy:
            "A model is already running or loading. Please try again when it finishes."
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

/// The system can report pressure before this process reaches its own allocation limit.
private final class MemoryPressureObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var pressured = false
    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))

    init() {
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.pressured = true }
        }
        source.resume()
    }

    var isUnderPressure: Bool { lock.withLock { pressured } }
    func stop() { source.cancel() }
    deinit { source.cancel() }
}
