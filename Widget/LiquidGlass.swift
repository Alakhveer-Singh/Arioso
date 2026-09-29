import AppKit
import SwiftUI

/// Liquid glass card: the desktop shows through, blurred and refracted, with
/// a soft moving tint from the current song's artwork and a bright rim.
struct LiquidGlassCard: ViewModifier {
    let backdrop: NSImage?
    let look: AppSettings.Look
    let glass: Bool
    let clarity: Double
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if glass { glassCard(content, shape: shape) } else { solidCard(content, shape: shape) }
    }

    /// The original look: moving album art (or a dark gradient), fully opaque.
    private func solidCard(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                if let backdrop {
                    DriftingBackground(image: backdrop, look: look)
                } else {
                    LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.19), Color(red: 0.03, green: 0.04, blue: 0.05)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func glassCard(_ content: Content, shape: RoundedRectangle) -> some View {
        let tinted = content
            .background {
                ZStack {
                    if let backdrop {
                        DriftingBackground(image: backdrop, look: look).opacity((1 - clarity) * 0.7)
                    }
                    // Keeps white text readable over bright wallpapers; the
                    // Darkness slider controls how much.
                    Color.black.opacity(look.backgroundDarkness * 0.45)
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2)
            )
        if #available(macOS 26.0, *) {
            tinted.glassEffect(clarity > 0.5 ? .clear : .regular, in: shape)
        } else {
            tinted.background(BehindWindowBlur().clipShape(shape))
        }
    }
}

/// Pre-macOS 26 fallback: frosted blur of whatever is behind the window.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    func liquidGlass(_ glass: Bool, clarity: Double, backdrop: NSImage?, look: AppSettings.Look, cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassCard(backdrop: backdrop, look: look, glass: glass, clarity: clarity, cornerRadius: cornerRadius))
    }
}
