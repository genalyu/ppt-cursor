import Carbon

final class AcceptShortcut {
    static var prefersTab: Bool {
        get { UserDefaults.standard.bool(forKey: "acceptWithTab") }
        set { UserDefaults.standard.set(newValue, forKey: "acceptWithTab") }
    }

    static func allowsTab(editingText: Bool?) -> Bool {
        prefersTab && editingText == false
    }

    private var key: EventHotKeyRef?
    private var registrationID: UInt32 = 0
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
            guard status == noErr, id.signature == 0x50505443 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<AcceptShortcut>.fromOpaque(data).takeUnretainedValue()
            guard shortcut.key != nil, id.id == shortcut.registrationID else { return OSStatus(eventNotHandledErr) }
            shortcut.accept()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func registerPreferred(useTab: Bool) -> String? {
        if useTab && enable(useTab: true) { return "Tab" }
        return enable() ? "⌥⌘↩" : nil
    }

    func enable(useTab: Bool = false) -> Bool {
        guard handler != nil else { return false }
        if key != nil { return true }
        registrationID &+= 1
        return RegisterEventHotKey(UInt32(useTab ? kVK_Tab : kVK_Return), useTab ? 0 : UInt32(optionKey | cmdKey),
                                   EventHotKeyID(signature: 0x50505443, id: registrationID),
                                   GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &key) == noErr
    }
    func disable() { if let key { UnregisterEventHotKey(key); self.key = nil } }
    deinit { disable(); if let handler { RemoveEventHandler(handler) } }
}
