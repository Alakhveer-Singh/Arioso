import AppKit
import Accelerate
import Combine
import CoreAudio

/// Live loudness of the music app's own audio, in a few frequency bands, for the player's waves.
///
/// It listens to Spotify or Apple Music only (a Core Audio "process tap", macOS 14.2 and later),
/// only while a song is playing, and only measures: each burst of audio is turned into a handful
/// of numbers and dropped. Nothing is recorded, saved or sent. macOS asks permission the first
/// time. When it isn't available, or isn't allowed, the waves fall back to the animated ones.
final class AudioLevels: ObservableObject {
    static let bandCount = 4
    static let shared = AudioLevels()

    /// True while real audio is being measured; the waves follow it instead of animating on their own.
    @Published private(set) var isLive = false

    /// 0.2 (calm) … 1 (reacts to everything). Set from Settings, read on the audio queue.
    static var sensitivity: Float {
        get { sensitivityLock.lock(); defer { sensitivityLock.unlock() }; return sensitivityValue }
        set { sensitivityLock.lock(); sensitivityValue = newValue; sensitivityLock.unlock() }
    }
    private static let sensitivityLock = NSLock()
    private static var sensitivityValue: Float = 0.5

    private let lock = NSLock()
    private var current = [Float](repeating: 0, count: AudioLevels.bandCount)   // guarded by lock
    private var lastSound = Date.distantPast                                    // guarded by lock
    private var cancellables = Set<AnyCancellable>()
    private weak var model: LyricsSceneModel?
    private var store: SettingsStore?
    /// The running tap, boxed so this class needs no availability annotation.
    private var tap: AnyObject?
    private var tapProcesses: [UInt32] = []
    private var pollTimer: Timer?
    private var liveTimer: Timer?

    /// The latest levels, 0…1 per band, lowest frequencies first.
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    // MARK: - When to listen

    func attach(model: LyricsSceneModel, store: SettingsStore) {
        self.model = model
        self.store = store
        model.$isPlaying.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reevaluate() }.store(in: &cancellables)
        model.$nowPlaying.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reevaluate() }.store(in: &cancellables)
        store.$settings.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reevaluate() }.store(in: &cancellables)
    }

    /// Listens while a song is playing, the player is showing, and Live waves is on.
    private func reevaluate() {
        guard #available(macOS 14.2, *) else { return }
        guard let model, let settings = store?.settings else { return }
        Self.sensitivity = Float(min(1, max(0.2, settings.waveSensitivity)))
        let playerWaves = settings.showNowPlaying && settings.playerWaves
        let wanted = settings.isEnabled && playerWaves && settings.playerLiveWaves
            && model.isPlaying && model.playerBundleID != nil
        if wanted, let bundleID = model.playerBundleID { start(bundleID: bundleID) } else { stop() }
    }

    @available(macOS 14.2, *)
    private func start(bundleID: String) {
        if pollTimer == nil {
            // The music app only shows up as an audio process once it's making sound, and it can
            // spawn helpers; look again every couple of seconds.
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.syncTap() }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
            let live = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.updateLive() }
            RunLoop.main.add(live, forMode: .common)
            liveTimer = live
        }
        syncTap()
    }

    @available(macOS 14.2, *)
    private func syncTap() {
        guard let bundleID = model?.playerBundleID else { return }
        let processes = Self.audioProcesses(bundleIDPrefix: bundleID)
        if processes.isEmpty {
            releaseTap()
            return
        }
        guard processes != tapProcesses || tap == nil else { return }
        releaseTap()
        tapProcesses = processes
        tap = ProcessTap(processes: processes) { [weak self] bands, sound in self?.receive(bands, sound: sound) }
    }

    private func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        liveTimer?.invalidate(); liveTimer = nil
        releaseTap()
        if isLive { isLive = false }
    }

    private func releaseTap() {
        tap = nil            // its deinit tears the tap down
        tapProcesses = []
        lock.lock()
        current = [Float](repeating: 0, count: Self.bandCount)
        lastSound = .distantPast
        lock.unlock()
    }

    // MARK: - Levels coming in (from the audio queue)

    private func receive(_ bands: [Float], sound: Bool) {
        lock.lock()
        current = bands
        if sound { lastSound = Date() }
        lock.unlock()
    }

    /// Live only while there has been sound in the last few seconds; a silent tap (permission
    /// declined, or nothing playing) keeps the animated waves instead of flat bars.
    private func updateLive() {
        lock.lock(); let heard = Date().timeIntervalSince(lastSound) < 4; lock.unlock()
        let live = heard && tap != nil
        if live != isLive { isLive = live }
        if ProcessInfo.processInfo.environment["ARIOSO_AUDIO_DEBUG"] != nil {
            let bands = snapshot().map { String(format: "%.2f", $0) }.joined(separator: " ")
            print("audio levels live=\(live) processes=\(tapProcesses.count) bands=\(bands)")
        }
    }

    // MARK: - Finding the music app's audio processes

    @available(macOS 14.2, *)
    private static func audioProcesses(bundleIDPrefix: String) -> [UInt32] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { bundleID(of: $0)?.hasPrefix(bundleIDPrefix) == true }.sorted()
    }

    @available(macOS 14.2, *)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(process, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - The tap

@available(macOS 14.2, *)
private final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.alakhveer.Arioso.AudioLevels", qos: .userInteractive)
    private var analyzer: SpectrumAnalyzer?
    private let onBands: ([Float], Bool) -> Void

    /// nil when macOS refuses (permission, or the processes have gone quiet).
    init?(processes: [UInt32], onBands: @escaping ([Float], Bool) -> Void) {
        self.onBands = onBands
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Arioso levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted      // it only listens; the music plays as normal
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format) == noErr,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { stop(); return nil }
        analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Arioso levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: 1]],
        ]
        if let output = Self.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else { stop(); return nil }

        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.handle(input, nonInterleaved: nonInterleaved)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else { stop(); return nil }
    }

    deinit { stop() }

    private func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    /// Mixes what just played down to mono and hands it to the analyzer; the audio itself goes no further.
    private func handle(_ input: UnsafePointer<AudioBufferList>, nonInterleaved: Bool) {
        guard let analyzer else { return }
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard list.count > 0 else { return }
        var mono: [Float]
        if nonInterleaved {
            let frames = Int(list[0].mDataByteSize) / MemoryLayout<Float>.size
            mono = [Float](repeating: 0, count: frames)
            for buffer in list {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                for i in 0..<n { mono[i] += data[i] / Float(list.count) }
            }
        } else {
            let buffer = list[0]
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            mono = [Float](repeating: 0, count: frames)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += data[f * channels + c] }
                mono[f] = sum / Float(channels)
            }
        }
        if let result = analyzer.push(mono) { onBands(result.bands, result.sound) }
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

// MARK: - Turning samples into band levels

/// 1024-sample FFT frames, folded into seven log-spaced bands from about 60 Hz to 12 kHz, with a
/// fast rise and a slower fall so the bars move like a level meter.
private final class SpectrumAnalyzer {
    private let size = 1024
    private let log2n: vDSP_Length = 10
    private let setup: FFTSetup
    private var window: [Float]
    private var pending: [Float] = []
    private var real: [Float]
    private var imag: [Float]
    private var smoothed = [Float](repeating: 0, count: AudioLevels.bandCount)
    /// Each band's recent peak in dB, fading slowly. Levels are measured against it, so every bar
    /// uses its full range whether the music is loud or quiet, bassy or bright.
    private var peaks = [Float](repeating: -45, count: AudioLevels.bandCount)
    /// FFT bin range for each band.
    private let ranges: [Range<Int>]

    init(sampleRate: Double) {
        setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, 1024, Int32(vDSP_HANN_NORM))
        real = [Float](repeating: 0, count: 512)
        imag = [Float](repeating: 0, count: 512)
        let edges: [Double] = [60, 220, 820, 3100, 12000]   // 4 bands, low to high, log-spaced
        let binWidth = sampleRate / 1024
        ranges = (0..<AudioLevels.bandCount).map { i in
            let lo = max(1, Int(edges[i] / binWidth))
            let hi = min(511, max(lo + 1, Int(edges[i + 1] / binWidth)))
            return lo..<hi
        }
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feeds new mono samples. Returns the newest band levels once a full frame has been analysed.
    func push(_ samples: [Float]) -> (bands: [Float], sound: Bool)? {
        pending.append(contentsOf: samples)
        var result: (bands: [Float], sound: Bool)?
        while pending.count >= size {
            result = analyze(Array(pending[0..<size]))
            pending.removeFirst(size / 2)            // 50% overlap: about 90 updates a second
        }
        return result
    }

    private func analyze(_ frame: [Float]) -> (bands: [Float], sound: Bool) {
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(size))
        var power = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(size / 2))
            }
        }
        var loudest: Float = -200
        let sensitivity = AudioLevels.sensitivity
        let attack = 0.1 + 0.4 * sensitivity
        for (i, range) in ranges.enumerated() {
            var sum: Float = 0
            for bin in range { sum += power[bin] }
            let mean = sum / Float(range.count)
            // Power relative to full scale, in dB; music falls off with frequency, so lift the highs a little.
            let db = 10 * log10(mean / Float(size * size) + 1e-12)
            loudest = max(loudest, db)
            peaks[i] = max(db, peaks[i] - 0.012)
            // Lower sensitivity spreads the bars over a wider range of loudness (smaller swings) and
            // makes them rise more gently.
            let range = 20 + (1 - sensitivity) * 40
            let level = peaks[i] < -75 ? 0 : min(1, max(0, (db - (peaks[i] - range)) / range))
            smoothed[i] = level > smoothed[i]
                ? smoothed[i] + (level - smoothed[i]) * attack
                : max(level, smoothed[i] - 0.04)
        }
        return (smoothed, loudest > -90)
    }
}
