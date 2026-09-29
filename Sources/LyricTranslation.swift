import Foundation
#if canImport(Translation)
import Translation
import SwiftUI
#endif

/// Turns non-Latin lyric text into Latin letters, entirely offline: no network,
/// no third party, works on every macOS version. This is the "Romanize" option,
/// for scripts like Gurmukhi, Devanagari, Japanese, Korean or Arabic.
enum Romanizer {
    static func romanize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != LyricsService.instrumentalMarker,
              !LyricsService.isMostlyLatin(trimmed) else { return nil }
        let mutable = NSMutableString(string: trimmed)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let result = (mutable as String).trimmingCharacters(in: .whitespaces)
        return result.isEmpty || result == trimmed ? nil : result
    }
}

#if canImport(Translation)

/// On-device translation of lyric lines with Apple's Translation framework
/// (macOS 15 and later). Nothing leaves the Mac: the system may ask, once, to
/// download the language pair, entirely locally.
///
/// A `TranslationSession` only exists inside a live `.translationTask`, so this
/// queues requested lines and runs them the next time that task fires; see
/// `TranslationHost`, mounted once in the Lyrics widget for the app's lifetime.
@available(macOS 15.0, *)
final class LyricTranslator: ObservableObject {
    static let shared = LyricTranslator()
    @Published fileprivate var configuration: TranslationSession.Configuration?

    private var cache: [String: String] = [:]
    private var queue: Set<String> = []
    private var target = "en"
    private var onFinished: [() -> Void] = []

    private func cacheKey(_ text: String, _ target: String) -> String { "\(target)::\(text)" }

    func cached(_ text: String, target: String) -> String? { cache[cacheKey(text, target)] }

    /// Queues any of `texts` not already translated, and asks the host to run them.
    /// `onUpdate` is called on the main thread once they're ready (or failed).
    func request(_ texts: [String], target: String, onUpdate: @escaping () -> Void) {
        self.target = target
        let missing = texts.filter { !$0.isEmpty && $0 != LyricsService.instrumentalMarker
            && cache[cacheKey($0, target)] == nil }
        guard !missing.isEmpty else { return }
        queue.formUnion(missing)
        onFinished.append(onUpdate)
        // A fresh Configuration always re-triggers .translationTask, even for the same languages.
        configuration = TranslationSession.Configuration(target: Locale.Language(identifier: target))
    }

    /// Runs whatever is queued through a live session. Called by TranslationHost.
    fileprivate func run(with session: TranslationSession) async {
        guard !queue.isEmpty else { return }
        let texts = Array(queue)
        queue.removeAll()
        do {
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            let responses = try await session.translations(from: requests)
            for (text, response) in zip(texts, responses) { cache[cacheKey(text, target)] = response.targetText }
        } catch {
            // Unsupported pair, or the language pack isn't installed: leave the subtitle off.
        }
        let handlers = onFinished
        onFinished = []
        await MainActor.run { handlers.forEach { $0() } }
    }
}

/// Invisible: mounted once so a `TranslationSession` is always available when a
/// translation is requested. See `LyricTranslator`.
@available(macOS 15.0, *)
struct TranslationHost: View {
    @ObservedObject private var translator = LyricTranslator.shared
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(translator.configuration) { session in
                await translator.run(with: session)
            }
    }
}

#endif
