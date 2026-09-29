import AppKit
import SwiftUI

/// Welcome tour. Shown once per build: preferences outlive the app, so a plain
/// "done" flag would hide the tour even after a fresh download of a new version.
/// build_app.sh stamps every build with a unique CFBundleVersion.
enum Onboarding {
    private static let doneKey = "onboardingDoneBuild"
    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static var isDone: Bool { UserDefaults.standard.string(forKey: doneKey) == build }
    static func markDone() { UserDefaults.standard.set(build, forKey: doneKey) }
}

final class OnboardingModel: ObservableObject {
    @Published var page = 0
}

private struct OnboardingPage {
    let title: String
    let text: String
    let visual: AnyView
    var isFinal: Bool = false
}

struct OnboardingView: View {
    @StateObject private var model: OnboardingModel
    let onFinish: () -> Void

    init(startPage: Int = 0, onFinish: @escaping () -> Void) {
        let model = OnboardingModel()
        model.page = startPage
        _model = StateObject(wrappedValue: model)
        self.onFinish = onFinish
    }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                title: "Meet Arioso",
                text: "Live, synced lyrics for what you're playing on Spotify or Apple Music, full screen and on your desktop.",
                visual: AnyView(Illustration(name: "tour1"))),
            OnboardingPage(
                title: "Lyrics, Full Screen",
                text: "Press ⌥⌘L anywhere and your song fills the screen. Esc or a click takes you back.",
                visual: AnyView(Illustration(name: "tour2"))),
            OnboardingPage(
                title: "Widgets on Your Desktop",
                text: "Your lyrics and Recently Played, right beside your work. Drag and resize them anywhere.",
                visual: AnyView(Illustration(name: "tour3"))),
            OnboardingPage(
                title: "Always Within Reach",
                text: "A slim player sits at the bottom of your screen, on top of every app. Click it for shuffle, previous, play or pause, next and repeat, and drag the progress bar to skip around. Waves follow the real loudness of your music.",
                visual: AnyView(Illustration(name: "tour5"))),
            OnboardingPage(
                title: "You're All Set",
                text: "Turn on Open at Login in Settings to keep your widgets and player after a restart.",
                visual: AnyView(ClosingVisual()),
                isFinal: true),
        ]
    }

    var body: some View {
        let page = pages[model.page]
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Theme.background, Theme.backgroundDeep], startPoint: .top, endPoint: .bottom)
                page.visual
                    .id(model.page)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            .frame(height: 560)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.65), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i == model.page ? 0.95 : 0.3))
                        .frame(width: i == model.page ? 26 : 8, height: 8)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(page.text)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 48)
            }
            .id(model.page)
            .transition(.opacity)
            Spacer(minLength: 0)

            Button(action: next) {
                Text(model.page == pages.count - 1 ? "Get Started" : "Next")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.backgroundDeep)
                    .frame(width: 240, height: 44)
                    .background(Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                               startPoint: .top, endPoint: .bottom)))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 34)
        }
        .frame(width: 640, height: 820)
        .background(Theme.backgroundDeep)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }

    private func next() {
        if model.page < pages.count - 1 {
            withAnimation(.easeOut(duration: 0.3)) { model.page += 1 }
        } else {
            onFinish()
        }
    }
}

/// Closing page: no photo needed, just the app icon with a soft glow.
private struct ClosingVisual: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 220))
                .frame(width: 440, height: 440)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 148, height: 148)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        }
        .frame(width: 640, height: 560)
    }
}

/// A tour illustration, filling the top area.
private struct Illustration: View {
    let name: String
    /// tour5 is a close-up product shot, not a wide scene: scaling it to fill the frame
    /// crops in past the point of recognizing the player, so it's scaled to fit instead.
    var fill: Bool { name != "tour5" }
    var body: some View {
        if let path = Bundle.main.path(forResource: name, ofType: "jpg"), let image = NSImage(contentsOfFile: path) {
            Group {
                if fill {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    // Burns its own rectangle out into the page background at the edges, instead of
                    // ending in a hard-edged box. Sized to the image's own fitted bounds so the fade
                    // reaches its corners, and elliptical (not circular) so it reaches evenly on all
                    // four sides of a non-square box, not just the corners.
                    let box = CGSize(width: 520, height: 520 * image.size.height / image.size.width)
                    ZStack {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: box.width, height: box.height)
                        Rectangle().fill(
                            EllipticalGradient(stops: [.init(color: .clear, location: 0.45),
                                                       .init(color: Theme.backgroundDeep, location: 1)],
                                              center: .center))
                            .frame(width: box.width, height: box.height)
                    }
                }
            }
            .frame(width: 640, height: 560)
            .clipped()
            .grayscale(1)   // black-and-white, to sit in the slate palette
        }
    }
}
