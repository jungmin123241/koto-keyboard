import Foundation

@MainActor
public final class TranslationCoordinator {
    public private(set) var state: TranslationState = .idle {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((TranslationState) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var activeKey: Key?
    private struct Key: Equatable {
        let text: String
        let target: String
        let contextVersion: Int
    }

    public init() {}
    deinit { task?.cancel() }

    public func reset() {
        generation += 1
        task?.cancel()
        task = nil
        activeKey = nil
        state = .idle
    }

    public func request(text: String, target: String, contextVersion: Int, delayMilliseconds: Int,
                        service: any TranslationService, force: Bool = false) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Key(text: normalized, target: target, contextVersion: contextVersion)
        if !force && key.text == activeKey?.text && key.target == activeKey?.target {
            // Spaces can move the replacement boundary without changing the translation.
            // The keyboard refreshes its document snapshot before this call.
            activeKey = key
            return
        }
        reset()
        guard Self.isEligible(normalized) else {
            state = .empty
            return
        }
        activeKey = key
        let ticket = generation
        let delay = max(0, min(700, delayMilliseconds))
        task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.state = .translating
                let result = try await service.translate(text: normalized, sourceLanguage: nil, targetLanguage: target)
                guard !Task.isCancelled, self.generation == ticket else { return }
                guard result.originalText == normalized, !result.translatedText.isEmpty else {
                    throw TranslationError.invalidResponse
                }
                self.state = .translated(result)
            } catch {
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.activeKey = nil // Allow a retry after failure.
                self.state = .failed((error as? TranslationError) ?? .server)
            }
        }
    }

    public static func isEligible(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 500,
              text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        // Do not send an incomplete Hangul composition or a lone Latin letter.
        if let last = text.unicodeScalars.last,
           (0x1100...0x11FF).contains(last.value) || (0x3131...0x318E).contains(last.value) { return false }
        if text.count == 1, text.unicodeScalars.allSatisfy({ $0.isASCII }) { return false }
        return true
    }
}
