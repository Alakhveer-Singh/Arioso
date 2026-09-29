import Foundation

struct LyricLine {
    let time: TimeInterval
    let text: String
}

enum LyricsResult {
    case synced([LyricLine])
    case plain(String)
    case none
}

/// What Musixmatch's licence requires alongside displayed lyrics.
struct LyricsCredit: Equatable {
    /// The song's copyright line, shown with the lyrics.
    let copyright: String
    /// Must be requested each time the lyrics are displayed.
    let trackingURL: URL?
}

/// Licensed lyrics from the Musixmatch API: time-synced where available
/// (matcher.subtitle.get, LRC timing), otherwise plain (matcher.lyrics.get).
///
/// Licence terms honoured here: lyrics are kept in memory only (never written
/// to disk), the tracking pixel is requested whenever lyrics are shown, and
/// the copyright line plus "Lyrics powered by Musixmatch" are displayed.
/// The API key comes from the MusixmatchAPIKey entry in Info.plist, which
/// build_app.sh fills from $MUSIXMATCH_API_KEY. Without a key (personal and
/// website builds), lyrics come from lrclib.net instead.
final class LyricsService {
    static let shared = LyricsService()

    private var memoryCache: [String: (result: LyricsResult, credit: LyricsCredit?)] = [:]
    private static let base = "https://api.musixmatch.com/ws/1.1/"

    private var apiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "MusixmatchAPIKey") as? String
        return key?.isEmpty == false ? key : nil
    }

    private func cacheKey(artist: String, title: String) -> String {
        "\(artist.lowercased())::\(title.lowercased())"
    }

    func fetchLyrics(
        artist: String,
        title: String,
        duration: TimeInterval,
        completion: @escaping (LyricsResult, LyricsCredit?) -> Void
    ) {
        if artist == Demo.artist, title == Demo.title, Demo.isOn {
            completion(.synced(Demo.lyrics), LyricsCredit(copyright: "Demo song written for Arioso", trackingURL: nil))
            return
        }
        let key = cacheKey(artist: artist, title: title)
        if let cached = memoryCache[key] {
            completion(cached.result, cached.credit)
            return
        }
        guard let apiKey else {
            // Personal and website builds without a Musixmatch key use lrclib.net
            // (free, community-sourced). App Store builds always have a key.
            fetchFromLrclib(key: key, artist: artist, title: title, duration: duration, completion: completion)
            return
        }

        var synced = [URLQueryItem(name: "subtitle_format", value: "lrc")]
        if duration > 0 {
            synced += [URLQueryItem(name: "f_subtitle_length", value: String(Int(duration.rounded()))),
                       URLQueryItem(name: "f_subtitle_length_max_deviation", value: "4")]
        }
        request("matcher.subtitle.get", artist: artist, title: title, apiKey: apiKey, extra: synced) { [weak self] body in
            if let subtitle = body?["subtitle"] as? [String: Any],
               let lrc = subtitle["subtitle_body"] as? String {
                let lines = Self.parseLRC(lrc)
                if !lines.isEmpty {
                    self?.finish(key, .synced(lines), Self.credit(from: subtitle), completion); return
                }
            }
            self?.request("matcher.lyrics.get", artist: artist, title: title, apiKey: apiKey, extra: []) { body in
                if let lyrics = body?["lyrics"] as? [String: Any],
                   let text = lyrics["lyrics_body"] as? String, !text.isEmpty {
                    self?.finish(key, .plain(text), Self.credit(from: lyrics), completion); return
                }
                self?.finish(key, .none, nil, completion)
            }
        }
    }

    /// Tells Musixmatch the lyrics were shown (required by the licence).
    func reportDisplayed(_ credit: LyricsCredit?) {
        guard let url = credit?.trackingURL else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    private func finish(_ key: String, _ result: LyricsResult, _ credit: LyricsCredit?,
                        _ completion: @escaping (LyricsResult, LyricsCredit?) -> Void) {
        DispatchQueue.main.async {
            self.memoryCache[key] = (result, credit)
            completion(result, credit)
        }
    }

    private static func credit(from payload: [String: Any]) -> LyricsCredit {
        let copyright = (payload["lyrics_copyright"] as? String ?? "")
            .components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let pixel = (payload["pixel_tracking_url"] as? String).flatMap(URL.init(string:))
        return LyricsCredit(copyright: copyright.trimmingCharacters(in: .whitespaces), trackingURL: pixel)
    }

    /// Calls a Musixmatch matcher endpoint; hands back message.body, or nil on any failure.
    private func request(_ method: String, artist: String, title: String, apiKey: String,
                         extra: [URLQueryItem], completion: @escaping ([String: Any]?) -> Void) {
        var components = URLComponents(string: Self.base + method)!
        components.queryItems = [URLQueryItem(name: "q_track", value: title),
                                 URLQueryItem(name: "q_artist", value: artist),
                                 URLQueryItem(name: "apikey", value: apiKey)] + extra
        guard let url = components.url else { return completion(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let header = message["header"] as? [String: Any],
                  header["status_code"] as? Int == 200,
                  let body = message["body"] as? [String: Any] else { return completion(nil) }
            completion(body)
        }.resume()
    }

    // MARK: - lrclib.net (fallback when there's no Musixmatch key)

    private func fetchFromLrclib(key: String, artist: String, title: String, duration: TimeInterval,
                                 completion: @escaping (LyricsResult, LyricsCredit?) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "artist_name", value: artist),
                                 URLQueryItem(name: "track_name", value: title)]
        guard let url = components.url else { return completion(.none, nil) }
        var request = URLRequest(url: url)
        request.setValue("Arioso/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let records = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
            let result = Self.bestLrclibResult(from: records, duration: duration)
            self?.finish(key, result, nil, completion)
        }.resume()
    }

    /// lrclib is community-edited, and a single record can be shifted by
    /// several seconds, so pick the synced record whose timing agrees with the
    /// majority of records of the same length.
    static func bestLrclibResult(from records: [[String: Any]], duration: TimeInterval) -> LyricsResult {
        let synced: [(lines: [LyricLine], firstLine: TimeInterval, duration: TimeInterval)] =
            records.compactMap { record in
                guard let raw = record["syncedLyrics"] as? String else { return nil }
                let lines = parseLRC(raw)
                guard let first = lines.first(where: { !$0.text.isEmpty }) else { return nil }
                return (lines, first.time, record["duration"] as? TimeInterval ?? 0)
            }
        let sameLength = synced.filter { duration <= 0 || abs($0.duration - duration) <= 4 }
        let timed = sameLength.isEmpty ? synced : sameLength
        // Prefer lyrics in the song's own script (Urdu, Hindi, Arabic, ...) over
        // romanized transliterations when lrclib has both.
        let nativeScript = timed.filter { !isMostlyLatin(replacingLookalikeLetters($0.lines.map(\.text).joined())) }
        let candidates = nativeScript.isEmpty ? timed : nativeScript
        if !candidates.isEmpty {
            let median = candidates.map(\.firstLine).sorted()[candidates.count / 2]
            let best = candidates.min { a, b in
                let da = abs(a.firstLine - median), db = abs(b.firstLine - median)
                return da != db ? da < db : abs(a.duration - duration) < abs(b.duration - duration)
            }!
            return .synced(best.lines.map { LyricLine(time: $0.time, text: replacingLookalikeLetters($0.text)) })
        }
        if let plain = records.lazy.compactMap({ $0["plainLyrics"] as? String }).first(where: { !$0.isEmpty }) {
            return .plain(replacingLookalikeLetters(plain))
        }
        return .none
    }

    static func parseLRC(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let timeTagRegex = try? NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]"#)

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let regex = timeTagRegex else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            let text = regex.stringByReplacingMatches(
                in: line, range: NSRange(location: 0, length: nsLine.length), withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)

            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound {
                    let fracString = nsLine.substring(with: match.range(at: 3))
                    let padded = fracString.count == 2 ? fracString + "0" : fracString
                    fraction = (Double(padded) ?? 0) / 1000.0
                }
                let time = minutes * 60 + seconds + fraction
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    static let instrumentalMarker = "♪"

    /// Turns blank LRC lines into ♪ and inserts ♪ into long stretches with no
    /// vocals (intros, solos). LRC has no end times, so a sung line is assumed
    /// to last `assumedLineDuration`.
    static func addingInstrumentalMarkers(to lines: [LyricLine]) -> [LyricLine] {
        let assumedLineDuration: TimeInterval = 6
        let minimumSilence: TimeInterval = 4

        var result: [LyricLine] = []
        var vocalsEnd: TimeInterval = 0
        for line in lines {
            let isBlank = line.text.trimmingCharacters(in: .whitespaces).isEmpty
            let lastIsMarker = result.last?.text == instrumentalMarker
            if isBlank {
                if !lastIsMarker { result.append(LyricLine(time: line.time, text: instrumentalMarker)) }
                vocalsEnd = line.time
            } else {
                if !lastIsMarker, line.time - vocalsEnd >= minimumSilence {
                    result.append(LyricLine(time: vocalsEnd, text: instrumentalMarker))
                }
                result.append(line)
                vocalsEnd = line.time + assumedLineDuration
            }
        }
        return result
    }

    // MARK: - Scripts

    private static func letters(in text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { $0.properties.isAlphabetic }
    }

    static func isMostlyLatin(_ text: String) -> Bool {
        let all = letters(in: text)
        return all.filter { $0.value < 0x0250 }.count * 2 >= all.count
    }

    /// Hebrew, Arabic, Urdu, Persian, Syriac, Thaana and related scripts.
    static func isRightToLeft(_ text: String) -> Bool {
        let all = letters(in: text)
        let rtl = all.filter {
            (0x0590...0x08FF).contains($0.value) || (0xFB1D...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value)
        }
        return !all.isEmpty && rtl.count * 2 > all.count
    }

    /// Maps look-alike symbols some lyric sources use for Latin letters
    /// (e.g. "ᗪum" for "Dum") back to plain letters. Fancy styled letters such as
    /// 𝐁𝐨𝐥𝐝 are folded by NFKC.
    private static let lookalikes: [Character: Character] = [
        "ᗩ": "A", "ᗷ": "B", "ᑕ": "C", "ᗪ": "D", "ᗴ": "E", "ᕮ": "E", "ᖴ": "F", "ᘜ": "G", "ᕼ": "H",
        "ᒍ": "J", "ᒪ": "L", "ᗰ": "M", "ᑎ": "N", "ᑭ": "P", "ᑫ": "Q", "ᖇ": "R", "ᔕ": "S",
        "ᑌ": "U", "ᐯ": "V", "ᗯ": "W", "᙭": "X", "ᘔ": "Z"
    ]

    static func replacingLookalikeLetters(_ text: String) -> String {
        String(text.precomposedStringWithCompatibilityMapping.map { lookalikes[$0] ?? $0 })
    }
}
