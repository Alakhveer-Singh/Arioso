import AppKit

/// Album covers as the player shows them, kept on disk (inside the app's
/// sandbox container) so Recently Played still has them later.
final class ArtworkService {
    static let shared = ArtworkService()

    private var cache: [String: NSImage] = [:]
    private var waiting: [String: [(NSImage) -> Void]] = [:]

    static func key(artist: String, title: String) -> String { "\(artist)::\(title)" }

    private var real: Set<String> = []
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Arioso/Artwork", isDirectory: true)

    private func file(for key: String) -> URL {
        let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(String(name.prefix(200)) + ".jpg")
    }

    func cached(artist: String, title: String) -> NSImage? {
        let key = Self.key(artist: artist, title: title)
        if let image = cache[key] { return image }
        guard let image = NSImage(contentsOf: file(for: key)) else { return nil }
        cache[key] = image
        real.insert(key)
        return image
    }

    /// The cover the player reported, saved to disk.
    func store(_ image: NSImage, artist: String, title: String) {
        let key = Self.key(artist: artist, title: title)
        guard !real.contains(key) else { return }
        real.insert(key)
        cache[key] = image
        waiting.removeValue(forKey: key)?.forEach { $0(image) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? jpeg.write(to: file(for: key))
        }
    }

    /// Downloads a cover from a URL the player reported (Spotify gives one).
    func download(from url: String, artist: String, title: String) {
        guard let url = URL(string: url), url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.store(image, artist: artist, title: title) }
        }.resume()
    }

    /// Calls back with the cover now if it's known, otherwise as soon as
    /// the player reports it for that song.
    func fetch(artist: String, title: String, completion: @escaping (NSImage) -> Void = { _ in }) {
        if let image = cached(artist: artist, title: title) { return completion(image) }
        waiting[Self.key(artist: artist, title: title), default: []].append(completion)
    }
}
