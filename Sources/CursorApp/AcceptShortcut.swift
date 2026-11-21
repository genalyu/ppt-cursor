import Carbon

final class AcceptShortcut {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let accept: () -> Void

    init(accept: @escaping () -> Void) {
        self.accept = accept
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, input, data in
            guard let input, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(input, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x50505443, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<AcceptShortcut>.fromOpaque(data).takeUnretainedValue()
            guard shortcut.key != nil else { return OSStatus(eventNotHandledErr) }
            shortcut.accept()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func enable(useTab: Bool = false) -> Bool {
        guard handler != nil else { return false }
        if key != nil { return true }
        return RegisterEventHotKey(UInt32(useTab ? kVK_Tab : kVK_Return), useTab ? 0 : UInt32(optionKey | cmdKey),
                                   EventHotKeyID(signature: 0x50505443, id: 1),
                                   GetApplicationEventTarget(), 0, &key) == noErr
    }
    func disable() { if let key { UnregisterEventHotKey(key); self.key = nil } }
    deinit { disable(); if let handler { RemoveEventHandler(handler) } }
}
