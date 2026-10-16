import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement
import CryptoKit
import ImageIO

// MARK: - Konfigurasi
let maxItems = 10                               // total item (pin + biasa)
let maxPins = 7                                 // maksimal item yang di-pin
let hotKeyCode = UInt32(kVK_ANSI_V)             // tombol V
let hotKeyModifiers = UInt32(cmdKey | shiftKey) // Cmd + Shift
let panelSize = NSSize(width: 360, height: 440)

// MARK: - Bahasa: ikut bahasa macOS (Indonesia atau Inggris)
let isIndonesian = (Locale.preferredLanguages.first ?? "en").hasPrefix("id")
func L(_ en: String, _ id: String) -> String { isIndonesian ? id : en }

// MARK: - Model
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var pinned = false
    var date = Date()
    var image: String? = nil      // nama file PNG di folder images (nil = teks)

    var isImage: Bool { image != nil }
}

let maxImageBytes = 60 * 1024 * 1024

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [Clip] = []
    @Published var selected = 0
    @Published var keyboardMoves = 0
    private let url: URL
    let imagesDir: URL
    private var thumbs: [String: NSImage] = [:]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")

        guard let data = try? Data(contentsOf: url) else { return }
        if let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            items = clips
        } else if let old = try? JSONDecoder().decode([String].self, from: data) {
            items = old.map { Clip(text: $0) } // format versi 1.0.x
        }
        items.removeAll { $0.isImage && !FileManager.default.fileExists(atPath: imageURL($0.image!).path) }
        trim()
        cleanupImages()
    }

    // MARK: Tambah
    func add(_ s: String) {
        insert(Clip(text: s)) { !$0.isImage && $0.text == s }
    }

    func addImage(png: Data) {
        guard png.count <= maxImageBytes else { return }
        let name = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + ".png"
        let file = imageURL(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard (try? png.write(to: file, options: .atomic)) != nil else { return }
        }
        insert(Clip(text: "", image: name)) { $0.image == name }
    }

    func bump(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var clip = items.remove(at: i)
        clip.date = Date()
        items.insert(clip, at: 0)
        save()
    }

    private func insert(_ new: Clip, matching same: (Clip) -> Bool) {
        var clip = new
        if let i = items.firstIndex(where: same) {
            clip = items.remove(at: i)
            clip.date = Date()
        }
        items.insert(clip, at: 0)
        trim()
        save()
    }

    // MARK: Gambar
    func imageURL(_ name: String) -> URL { imagesDir.appendingPathComponent(name) }

    func imageData(_ clip: Clip) -> Data? {
        guard let name = clip.image else { return nil }
        return try? Data(contentsOf: imageURL(name))
    }

    func thumbnail(_ name: String) -> NSImage? {
        if let t = thumbs[name] { return t }
        guard let src = CGImageSourceCreateWithURL(imageURL(name) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbs[name] = img
        return img
    }

    func imageSize(_ name: String) -> String {
        guard let src = CGImageSourceCreateWithURL(imageURL(name) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return "" }
        return "\(w)×\(h)"
    }

    // Hapus file gambar yang sudah tidak dipakai
    private func cleanupImages() {
        let used = Set(items.compactMap(\.image))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
        for f in files where !used.contains(f) {
            try? FileManager.default.removeItem(at: imageURL(f))
            thumbs[f] = nil
        }
    }

    // MARK: Pin & hapus
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
        cleanupImages()
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
                Text("\(store.pinCount)/\(maxPins) " + L("pinned", "pin"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Clear all", "Hapus semua")) { store.clearUnpinned() }
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
                    Text(L("No history yet", "Belum ada riwayat"))
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
                                    thumbnail: clip.image.flatMap { store.thumbnail($0) },
                                    imageInfo: clip.image.map { store.imageSize($0) } ?? "",
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

            Text(L("↑↓ select  ·  Enter paste  ·  Del delete  ·  Esc close", "↑↓ pilih  ·  Enter paste  ·  Del hapus  ·  Esc tutup"))
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
    let thumbnail: NSImage?
    let imageInfo: String
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        let showActions = hover || selected
        HStack(alignment: .top, spacing: 6) {
            Group {
                if clip.isImage {
                    VStack(alignment: .leading, spacing: 4) {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 90, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(L("Image", "Gambar") + (imageInfo.isEmpty ? "" : "  ·  \(imageInfo)"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)))
                        .font(.system(size: 12))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                IconButton(name: clip.pinned ? "pin.fill" : "pin",
                           help: clip.pinned ? L("Unpin", "Lepas pin") : (canPin ? L("Pin", "Pin") : L("Max \(maxPins) pins", "Maksimal \(maxPins) pin")),
                           action: onPin)
                    .opacity(clip.pinned ? 1 : (showActions ? (canPin ? 1 : 0.3) : 0))
                    .disabled(!canPin)
                IconButton(name: "trash", help: L("Delete", "Hapus"), action: onDelete)
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

// MARK: - Auto-update dari GitHub Releases
struct GHRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: String }
    let tag_name: String
    let assets: [Asset]
}

@MainActor
final class Updater {
    static let repo = "yahyahouse/copy-paste-history"
    private(set) var status = ""
    private var busy = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check(manual: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: req)
                let rel = try JSONDecoder().decode(GHRelease.self, from: data)
                let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

                guard Self.isNewer(latest, than: currentVersion),
                      let asset = rel.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                      let url = URL(string: asset.browser_download_url) else {
                    status = L("Up to date", "Sudah versi terbaru")
                    if manual { Self.alert(L("Clip History is up to date (v\(currentVersion)).", "Clip History sudah versi terbaru (v\(currentVersion)).")) }
                    return
                }

                let appPath = Bundle.main.bundlePath
                if appPath.contains("/AppTranslocation/") || appPath.hasPrefix("/Volumes/") {
                    status = L("Move the app to Applications to update", "Pindahkan app ke Applications untuk update")
                    if manual { Self.alert(L("Move Clip History to the Applications folder so it can update itself.", "Pindahkan Clip History ke folder Applications dulu supaya bisa update otomatis.")) }
                    return
                }

                status = L("Downloading v\(latest)…", "Mengunduh v\(latest)…")
                let (tmp, _) = try await URLSession.shared.download(from: url)
                let target = URL(fileURLWithPath: appPath)
                try await Task.detached { try Self.install(dmgAt: tmp, replacing: target) }.value
                Self.relaunch(target)
            } catch {
                status = L("Update failed", "Gagal update")
                if manual { Self.alert(L("Couldn't check for updates: ", "Gagal cek update: ") + error.localizedDescription) }
            }
        }
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    nonisolated static func install(dmgAt tmp: URL, replacing target: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ClipHistoryUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let dmg = work.appendingPathComponent("update.dmg")
        try fm.moveItem(at: tmp, to: dmg)

        let mount = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-quiet", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }

        let staged = work.appendingPathComponent("ClipHistory.app")
        try run("/usr/bin/ditto", [mount.appendingPathComponent("ClipHistory.app").path, staged.path])
        _ = try fm.replaceItemAt(target, withItemAt: staged)
    }

    nonisolated static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "ClipHistory", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(path) " + L("failed", "gagal") + " (\(p.terminationStatus))"])
        }
    }

    static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Clip History"
        a.informativeText = text
        a.runModal()
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
    let updater = Updater()
    var statusItem: NSStatusItem!
    var panel: ClipPanel!
    var lastChange = NSPasteboard.general.changeCount
    var hotKeyRef: EventHotKeyRef?
    var keyMonitor: Any?
    var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "Clip History")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        buildPanel()

        let timer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                         selector: #selector(poll), userInfo: nil, repeats: true)
        timer.tolerance = 0.2

        registerHotKey()

        // Cek update 10 detik setelah buka, lalu tiap 6 jam
        perform(#selector(autoUpdate), with: nil, afterDelay: 10)
        Timer.scheduledTimer(timeInterval: 6 * 3600, target: self,
                             selector: #selector(autoUpdate), userInfo: nil, repeats: true)
    }

    @objc func autoUpdate() {
        guard !panel.isVisible else { return }
        updater.check(manual: false)
    }

    @objc func manualUpdate() { updater.check(manual: true) }

    // MARK: Clipboard watcher
    @objc func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount

        // Abaikan data sensitif dari password manager
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") ||
           types.contains("org.nspasteboard.TransientType") { return }

        // Teks didahulukan (copy file di Finder juga berisi ikon, jangan disimpan sebagai gambar)
        if let s = pb.string(forType: .string),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.add(s)
            return
        }

        // Gambar: screenshot ke clipboard, copy image dari browser, dll.
        if let png = imagePNG(from: pb) {
            store.addImage(png: png)
        }
    }

    // Ambil gambar dari clipboard dalam bentuk PNG (PNG, TIFF screenshot, JPEG, HEIC, dll.)
    func imagePNG(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }

        // Screenshot macOS sering berupa TIFF tanpa kompresi, bisa puluhan MB di layar besar
        if let tiff = pb.data(forType: .tiff), tiff.count <= 300 * 1024 * 1024,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }

        // Format lain (JPEG, HEIC, PDF, dll.) lewat NSImage
        if pb.canReadObject(forClasses: [NSImage.self], options: nil),
           let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
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
        if clip.isImage {
            guard let png = store.imageData(clip) else { NSSound.beep(); return }
            pb.declareTypes([.png, .tiff], owner: nil)
            pb.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        } else {
            pb.setString(clip.text, forType: .string)
        }
        lastChange = pb.changeCount
        store.bump(clip.id)
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

        let open = NSMenuItem(title: L("Open Clipboard", "Buka Clipboard"), action: #selector(showPanel), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: L("Enable Auto-Paste…", "Aktifkan Auto-Paste…"), action: #selector(requestAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }

        let login = NSMenuItem(title: L("Open at Login", "Buka saat Login"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let clear = NSMenuItem(title: L("Clear All (except pinned)", "Hapus Semua (kecuali pin)"), action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let version = NSMenuItem(title: L("Version", "Versi") + " \(updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        if !updater.status.isEmpty {
            let st = NSMenuItem(title: updater.status, action: nil, keyEquivalent: "")
            st.isEnabled = false
            menu.addItem(st)
        }

        let upd = NSMenuItem(title: L("Check for Updates", "Cek Update"), action: #selector(manualUpdate), keyEquivalent: "")
        upd.target = self
        menu.addItem(upd)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Quit", "Keluar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
