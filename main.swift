import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Konfigurasi
let maxItems = 10                               // total item (pin + biasa)
let maxPins = 7                                 // maksimal item yang di-pin
let hotKeyCode = UInt32(kVK_ANSI_V)             // tombol V
let hotKeyModifiers = UInt32(cmdKey | shiftKey) // Cmd + Shift
let panelSize = NSSize(width: 360, height: 440)

// MARK: - Model
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var pinned = false
    var date = Date()
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [Clip] = []
    @Published var selected = 0
    @Published var keyboardMoves = 0
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")

        guard let data = try? Data(contentsOf: url) else { return }
        if let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            items = clips
        } else if let old = try? JSONDecoder().decode([String].self, from: data) {
            items = old.map { Clip(text: $0) } // format versi 1.0.x
        }
        trim()
    }

    func add(_ s: String) {
        var clip = Clip(text: s)
        if let i = items.firstIndex(where: { $0.text == s }) {
            clip = items.remove(at: i)
            clip.date = Date()
        }
        items.insert(clip, at: 0)
        trim()
        save()
    }

    var pinCount: Int { items.filter(\.pinned).count }
    var canPinMore: Bool { pinCount < maxPins }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if !items[i].pinned && !canPinMore {
            NSSound.beep()
            return
        }
        items[i].pinned.toggle()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        selected = max(0, min(selected, items.count - 1))
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        selected = 0
        save()
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = max(0, min(items.count - 1, selected + delta))
        keyboardMoves += 1
    }

    // Sisa slot setelah pin dipakai item biasa, yang paling lama dibuang
    private func trim() {
        let slots = max(0, maxItems - pinCount)
        var unpinned = 0
        items = items.filter { c in
            if c.pinned { return true }
            unpinned += 1
            return unpinned <= slots
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Tampilan
struct ClipboardView: View {
    @ObservedObject var store: Store
    let onPick: (Clip) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard").font(.system(size: 13, weight: .semibold))
                Text("\(store.pinCount)/\(maxPins) pin")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Hapus semua") { store.clearUnpinned() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .disabled(store.items.allSatisfy(\.pinned))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Belum ada riwayat")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { i, clip in
                                ClipRow(
                                    clip: clip,
                                    selected: i == store.selected,
                                    canPin: clip.pinned || store.canPinMore,
                                    onPin: { store.togglePin(clip.id) },
                                    onDelete: { store.remove(clip.id) }
                                )
                                .id(clip.id)
                                .onTapGesture { onPick(clip) }
                                .onHover { if $0 { store.selected = i } }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: store.keyboardMoves) { _ in
                        guard store.items.indices.contains(store.selected) else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(store.items[store.selected].id)
                        }
                    }
                }
            }

            Divider()

            Text("↑↓ pilih  ·  Enter paste  ·  Del hapus  ·  Esc tutup")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
        .frame(width: panelSize.width, height: panelSize.height)
    }
}

struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    let canPin: Bool
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        let showActions = hover || selected
        HStack(alignment: .top, spacing: 6) {
            Text(String(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)))
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                IconButton(name: clip.pinned ? "pin.fill" : "pin",
                           help: clip.pinned ? "Lepas pin" : (canPin ? "Pin" : "Maksimal \(maxPins) pin"),
                           action: onPin)
                    .opacity(clip.pinned ? 1 : (showActions ? (canPin ? 1 : 0.3) : 0))
                    .disabled(!canPin)
                IconButton(name: "trash", help: "Hapus", action: onDelete)
                    .opacity(showActions ? 1 : 0)
                    .disabled(!showActions)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let name: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: - Panel
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var panel: ClipPanel!
    var lastChange = NSPasteboard.general.changeCount
    var hotKeyRef: EventHotKeyRef?
    var keyMonitor: Any?
    var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "ClipHistory")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        buildPanel()

        let timer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                         selector: #selector(poll), userInfo: nil, repeats: true)
        timer.tolerance = 0.2

        registerHotKey()
    }

    // MARK: Clipboard watcher
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

    // MARK: Panel
    func buildPanel() {
        panel = ClipPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: ClipboardView(store: store) { [weak self] clip in
            self?.pick(clip)
        })
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect
    }

    @objc func showPanel() {
        if panel.isVisible { hidePanel(); return }
        store.selected = 0

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let x = min(max(mouse.x, vf.minX + 8), vf.maxX - panelSize.width - 8)
        let y = min(max(mouse.y - panelSize.height, vf.minY + 8), vf.maxY - panelSize.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return e }
                return self.handleKey(e) ? nil : e
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    func windowDidResignKey(_ notification: Notification) { hidePanel() }

    func handleKey(_ e: NSEvent) -> Bool {
        switch Int(e.keyCode) {
        case kVK_Escape:
            hidePanel()
        case kVK_DownArrow:
            store.move(1)
        case kVK_UpArrow:
            store.move(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if store.items.indices.contains(store.selected) { pick(store.items[store.selected]) }
        case kVK_Delete, kVK_ForwardDelete:
            if store.items.indices.contains(store.selected) { store.remove(store.items[store.selected].id) }
        default:
            if let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n),
               store.items.indices.contains(n - 1) {
                pick(store.items[n - 1])
            } else {
                return false
            }
        }
        return true
    }

    func pick(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(clip.text, forType: .string)
        lastChange = pb.changeCount
        store.add(clip.text)
        hidePanel()

        if AXIsProcessTrusted() {
            perform(#selector(pasteToFrontApp), with: nil, afterDelay: 0.1)
        } else {
            requestAccessibility()
        }
    }

    // MARK: Paste otomatis (Cmd+V ke aplikasi aktif)
    @objc func pasteToFrontApp() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @objc func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Menu bar
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Buka Clipboard", action: #selector(showPanel), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
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

        let clear = NSMenuItem(title: "Hapus Semua (kecuali pin)", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Keluar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc func clearAll() { store.clearUnpinned() }

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

    // MARK: Hotkey global
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon hotkey handler selalu jalan di main thread
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().showPanel()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x434C4950), id: 1) // "CLIP"
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Entry point
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
