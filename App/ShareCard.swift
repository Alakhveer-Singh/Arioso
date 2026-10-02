import AppKit

/// Turns the current lyric line into a shareable wide card: the album art on the
/// left, the song title and the line itself beside it, and an "Arioso" wordmark
/// underneath. Copied to the clipboard and saved to ~/Pictures/Arioso.
enum ShareCard {
    private static let size = CGSize(width: 1760, height: 780)
    private static let margin: CGFloat = 56
    private static let cornerRadius: CGFloat = 48

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
            // The whole card is one rounded rect; everything outside it stays transparent,
            // so it drops onto a page or a chat bubble without a hard rectangular edge.
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            drawBackground(in: rect)
            let coverFrame = drawCover(in: rect, artwork: artwork)
            drawText(in: rect, coverFrame: coverFrame, line: line, title: title, artist: artist)
            drawWordmark(in: rect, coverFrame: coverFrame)
            return true
        }
    }

    private static func drawBackground(in rect: CGRect) {
        NSGradient(colors: [NSColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1),
                            NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)])?
            .draw(in: rect, angle: -60)
    }

    /// Cover art, left edge, filling the card's height minus the margin. Returns its frame
    /// so the text and wordmark can line up against it.
    @discardableResult
    private static func drawCover(in rect: CGRect, artwork: NSImage?) -> CGRect {
        let side = rect.height - margin * 2
        let frame = CGRect(x: margin, y: margin, width: side, height: side)
        let path = NSBezierPath(roundedRect: frame, xRadius: 22, yRadius: 22)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        (artwork ?? placeholderCover()).draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        return frame
    }

    private static func placeholderCover() -> NSImage {
        NSImage(size: NSSize(width: 220, height: 220), flipped: false) { rect in
            NSColor(white: 0.3, alpha: 1).setFill()
            rect.fill()
            return true
        }
    }

    /// A serif "New York" if it's available (macOS 12+), else Georgia, else the system serif fallback.
    private static func serifFont(size: CGFloat) -> NSFont {
        NSFont(name: "New York", size: size) ?? NSFont(name: "Georgia", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    private static func drawText(in rect: CGRect, coverFrame: CGRect, line: String, title: String, artist: String) {
        let textX = coverFrame.maxX + margin
        let textWidth = rect.width - textX - margin

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont(size: 46),
            .foregroundColor: NSColor.white,
        ]
        let titleRect = CGRect(x: textX, y: rect.height - margin - 8 - 56, width: textWidth, height: 56)
        title.uppercased().draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: titleAttrs)

        let lineStyle = NSMutableParagraphStyle()
        lineStyle.lineBreakMode = .byWordWrapping
        lineStyle.lineSpacing = 8
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: lineStyle,
        ]
        let quoted = "\u{201C}\(line)\u{201D}"
        let quoteTop = titleRect.minY - 28
        let quoteRect = CGRect(x: textX, y: margin, width: textWidth, height: quoteTop - margin)
        quoted.draw(with: CGRect(x: quoteRect.minX, y: quoteRect.minY, width: quoteRect.width, height: quoteTop - margin),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: lineAttrs)
    }

    /// Arioso's own app icon plus "Shared by Arioso", bottom-left of the text column.
    private static func drawWordmark(in rect: CGRect, coverFrame: CGRect) {
        let iconSide: CGFloat = 44
        let iconFrame = CGRect(x: coverFrame.maxX + margin, y: margin, width: iconSide, height: iconSide)
        let icon = NSApp.applicationIconImage ?? placeholderCover()
        let path = NSBezierPath(roundedRect: iconFrame, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        icon.draw(in: iconFrame)
        NSGraphicsContext.restoreGraphicsState()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let label = "Shared by Arioso" as NSString
        let labelSize = label.size(withAttributes: labelAttrs)
        label.draw(at: CGPoint(x: iconFrame.maxX + 14, y: iconFrame.midY - labelSize.height / 2), withAttributes: labelAttrs)
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
