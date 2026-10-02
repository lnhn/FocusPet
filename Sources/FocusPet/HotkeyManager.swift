import Carbon

/// 全局快捷键（Carbon RegisterEventKey，无需辅助功能权限）
/// 默认 ⇧⌘P：空闲→开始专注；专注中→暂停；暂停中→继续。
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    var onTrigger: (() -> Void)?

    /// 注册快捷键；重复调用会先注销旧键
    func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_P),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    ) {
        unregister()
        installHandlerOnce()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4650_4554), id: 1)  // 签名 'FPET'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            print("[FocusPet] 快捷键注册失败，错误码 \(status)")
            fflush(stdout)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregister()
    }

    private func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onTrigger?()
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
}
