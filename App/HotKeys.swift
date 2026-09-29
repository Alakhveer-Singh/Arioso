import Carbon.HIToolbox

/// Global shortcuts. ⌥⌘L (full-screen lyrics) uses Carbon's RegisterEventHotKey,
/// which works inside the App Sandbox and needs no Accessibility permission.
/// ⌘⇧L (fit windows between widgets) needs Accessibility, since it moves
/// other apps' windows — see Reframe.swift.
final class HotKeys {
    static let shared = HotKeys()

    var onFullScreen: (() -> Void)?
    var onReframe: (() -> Void)?

    private var fullScreenRef: EventHotKeyRef?
    private var reframeRef: EventHotKeyRef?
    private var handlerInstalled = false

    func update(fullScreenEnabled: Bool) {
        installHandlerOnce()
        if let ref = fullScreenRef {
            UnregisterEventHotKey(ref)
            fullScreenRef = nil
        }
        guard fullScreenEnabled else { return }
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(optionKey | cmdKey),
                            EventHotKeyID(signature: OSType(0x4C595253), id: 1), // "LYRS"
                            GetApplicationEventTarget(), 0, &fullScreenRef)
    }

    func update(reframeEnabled: Bool) {
        installHandlerOnce()
        if let ref = reframeRef {
            UnregisterEventHotKey(ref)
            reframeRef = nil
        }
        guard reframeEnabled else { return }
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | shiftKey),
                            EventHotKeyID(signature: OSType(0x4C595253), id: 2),
                            GetApplicationEventTarget(), 0, &reframeRef)
    }

    private func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async {
                if id.id == 2 { HotKeys.shared.onReframe?() } else { HotKeys.shared.onFullScreen?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
