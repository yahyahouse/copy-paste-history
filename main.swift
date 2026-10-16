import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Konfigurasi
let maxItems = 50
let hotKeyCode = UInt32(kVK_ANSI_V)            // tombol V
let hotKeyModifiers = UInt32(cmdKey | shiftKey) // Cmd + Shift

// MARK: - Penyimpanan riwayat
final class Store {
    private(set) var items: [String] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            items = saved
        }
    }

    func add(_ s: String) {
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
        save()
    }

    func remove(at i: Int) {
        guard items.indices.contains(i) else { return }
        items.remove(at: i)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - App
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var lastChange = NSPasteboard.general.changeCount
    var hotKeyRef: EventHotKeyRef?
    var openedByHotKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "Clip History")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let timer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                         selector: #selector(poll), userInfo: nil, repeats: true)
        timer.tolerance = 0.2

        registerHotKey()
    }

    // Cek clipboard berubah atau tidak (hemat: hanya baca changeCount)
    @objc func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount

        // Abaikan data sensitif dari password manager
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") ||
           types.contains("org.nspasteboard.TransientType") { return }

        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.add(s)
    }

    // MARK: Menu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if store.items.isEmpty {
            let empty = NSMenuItem(title: "Belum ada riwayat", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (i, s) in store.items.enumerated() {
            let key = i < 9 ? "\(i + 1)" : ""
            let item = NSMenuItem(title: preview(s), action: #selector(pick(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.tag = i
            item.toolTip = String(s.prefix(500))

            // Tahan Option untuk hapus satu item
            let del = NSMenuItem(title: "Hapus: " + preview(s), action: #selector(removeOne(_:)), keyEquivalent: "")
            del.target = self
            del.tag = i
            del.isAlternate = true
            del.keyEquivalentModifierMask = .option

            menu.addItem(item)
            menu.addItem(del)
        }

        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: "Aktifkan Auto-Paste…", action: #selector(requestAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }

        let login = NSMenuItem(title: "Buka saat Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let clear = NSMenuItem(title: "Hapus Semua Riwayat", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let quit = NSMenuItem(title: "Keluar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    func preview(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > 60 ? String(flat.prefix(60)) + "…" : flat
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard store.items.indices.contains(sender.tag) else { return }
        let s = store.items[sender.tag]
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChange = pb.changeCount
        store.add(s)

        if openedByHotKey && AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.pasteToFrontApp() }
        }
    }

    @objc func removeOne(_ sender: NSMenuItem) { store.remove(at: sender.tag) }

    @objc func clearAll() { store.clear() }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Paste otomatis (Cmd+V ke aplikasi aktif)
    func pasteToFrontApp() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Hotkey global
    func showMenuAtMouse() {
        guard let menu = statusItem.menu else { return }
        openedByHotKey = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        DispatchQueue.main.async { self.openedByHotKey = false }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.showMenuAtMouse() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x434C4950), id: 1) // "CLIP"
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
