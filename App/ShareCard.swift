import AppKit
import CoreImage

/// Turns the current lyric line into a shareable square image: the album
/// art, softly blurred, behind the cover and the line itself. Copied to the
/// clipboard and saved to ~/Pictures/Arioso.
enum ShareCard {
    private static let size = CGSize(width: 1200, height: 1200)

    /// Builds the card for whatever's playing right now, or nil if nothing is.
    static func generate(from model: LyricsSceneModel) -> NSImage? {
        guard let info = model.nowPlaying else { return nil }
        let line: String
        if case .synced(let lines) = model.lyricsResult,
           let i = model.currentLineIndex, lines.indices.contains(i), !lines[i].text.isEmpty {
            line = lines[i].text
        } else {
            line = info.title
        }
        return render(line: line, title: info.title, artist: info.artist, artwork: info.artwork)
    }

    private static func render(line: String, title: String, artist: String, artwork: NSImage?) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            drawBackground(in: rect, artwork: artwork)
            drawCover(in: rect, artwork: artwork)
            drawText(in: rect, line: line, title: title, artist: artist)
            drawWordmark(in: rect)
            return true
        }
    }

    private static func drawBackground(in rect: CGRect, artwork: NSImage?) {
        if let artwork, let blurred = blur(artwork, radius: 60) {
            blurred.draw(in: rect.insetBy(dx: -40, dy: -40), from: .zero, operation: .copy, fraction: 1)
        } else {
            NSGradient(colors: [NSColor(red: 0.16, green: 0.21, blue: 0.27, alpha: 1),
                                NSColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1)])?
                .draw(in: rect, angle: -60)
        }
        NSColor.black.withAlphaComponent(0.42).setFill()
        rect.fill()
    }

    private static func blur(_ image: NSImage, radius: CGFloat) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: image.size)
    }

    /// Cover art, upper-left, with a rounded corner and a soft shadow.
    private static func drawCover(in rect: CGRect, artwork: NSImage?) {
        let side: CGFloat = 220
        let origin = CGPoint(x: 90, y: rect.height - 90 - side)
        let frame = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let path = NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.set()
        (artwork ?? placeholderCover()).draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        (artwork ?? placeholderCover()).draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func placeholderCover() -> NSImage {
        NSImage(size: NSSize(width: 220, height: 220), flipped: false) { rect in
            NSColor(white: 0.3, alpha: 1).setFill()
            rect.fill()
            return true
        }
    }

    private static func drawText(in rect: CGRect, line: String, title: String, artist: String) {
        let margin: CGFloat = 90
        let textWidth = rect.width - margin * 2

        let lineStyle = NSMutableParagraphStyle()
        lineStyle.lineBreakMode = .byWordWrapping
        lineStyle.lineSpacing = 6
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: lineStyle,
        ]
        let quoted = "\u{201C}\(line)\u{201D}"
        let lineRect = CGRect(x: margin, y: 260, width: textWidth, height: rect.height - 260 - 300)
        // Bottom-align by measuring first, then drawing at the bottom of the box.
        let measured = quoted.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin], attributes: lineAttrs)
        let drawRect = CGRect(x: lineRect.minX, y: lineRect.maxY - measured.height,
                              width: textWidth, height: measured.height)
        quoted.draw(with: drawRect, options: [.usesLineFragmentOrigin], attributes: lineAttrs)

        let songAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let artistAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        title.draw(at: CGPoint(x: margin, y: 170), withAttributes: songAttrs)
        if !artist.isEmpty {
            artist.draw(at: CGPoint(x: margin, y: 130), withAttributes: artistAttrs)
        }
    }

    private static func drawWordmark(in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        "♪ Arioso".draw(at: CGPoint(x: 90, y: rect.height - 70), withAttributes: attrs)
    }

    // MARK: - Delivery

    /// Copies the image to the clipboard and saves a PNG under
    /// ~/Pictures/Arioso, returning the saved file's URL.
    @discardableResult
    static func share(_ image: NSImage) -> URL? {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arioso", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let file = folder.appendingPathComponent("Arioso Lyric \(formatter.string(from: Date())).png")
        try? png.write(to: file)
        return file
    }
}
