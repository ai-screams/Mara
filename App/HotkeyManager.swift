import Carbon.HIToolbox
import AppKit

/// Manages a global Carbon hotkey for the application.
///
/// **Threading:** This class must be used exclusively from the main thread.
/// Carbon hotkey callbacks fire on the main run loop, and `register()`/`unregister()`/
/// `deinit` must also run on the main thread. The `Unmanaged.passUnretained(self)`
/// context pointer passed to `InstallEventHandler` is safe because `unregister()` and
/// `deinit` always execute on the main thread before the object is freed, guaranteeing
/// the callback can never fire with a stale pointer.
@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onToggle: () -> Void
    private let signature = OSType(0x534C5053) // 'SLPS'

    init(onToggle: @escaping () -> Void) { self.onToggle = onToggle }

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_K),
                  modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            MainActor.assumeIsolated {
                let me = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                me.onToggle()
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        dispatchPrecondition(condition: .onQueue(.main))
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil; eventHandler = nil
    }

    deinit {
        MainActor.assumeIsolated { unregister() }
    }
}
