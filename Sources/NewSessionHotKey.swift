import Carbon.HIToolbox

final class NewSessionHotKey {
    static let keyCode = UInt32(kVK_ANSI_N)
    static let modifiers = UInt32(controlKey | optionKey)
    static let label = "⌃⌥N"

    private let onTrigger: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var isRegistered = false

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() {
        guard !isRegistered else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<NewSessionHotKey>.fromOpaque(userData).takeUnretainedValue().onTrigger()
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr else { return }
        let identifier = EventHotKeyID(signature: OSType(0x43544B59), id: 1)
        isRegistered = RegisterEventHotKey(Self.keyCode, Self.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
