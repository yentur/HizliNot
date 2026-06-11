import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Floating panel that can still receive keyboard focus while not activating the app

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {

    var panel: NotePanel!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var clipTimer: Timer?
    var lastChangeCount: Int = 0
    var shelf: ShelfPanel!
    let shake = ShakeMonitor()
    var noteBlur: NSVisualEffectView?
    var preZoomFrame: NSRect?
    var preCollapseHeight: CGFloat?

    let minW: CGFloat = 320
    let minH: CGFloat = 300

    lazy var stateURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HizliNot", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }()

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon — it's a widget
        buildPanel()
        buildStatusItem()
        registerHotKey()
        startClipboardWatch()
        setupShelf()
        showPanel()
    }

    // MARK: Dropover-style shelf + shake-to-summon

    func setupShelf() {
        shelf = ShelfPanel()
        FileStore.shared.onChange = { [weak self] in
            self?.shelf.refresh()
            self?.pushFilesToWeb()
        }
        shake.onShake = { [weak self] in
            self?.shelf.showNear(NSEvent.mouseLocation)
        }
        shake.start()
    }

    func showShelf() { shelf.showNear(NSEvent.mouseLocation) }

    func pushFilesToWeb() {
        let arr = FileStore.shared.items.map { it -> [String: Any] in
            ["id": it.id, "name": it.name, "size": fmtSize(it.size),
             "isImage": it.isImage, "ext": it.ext, "thumb": it.thumbDataURL()]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let json = String(data: data, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.__setFiles && window.__setFiles(\(json));", completionHandler: nil)
    }

    func fmtSize(_ b: Int) -> String {
        if b < 1024 { return "\(b) B" }
        if b < 1048576 { return String(format: "%.1f KB", Double(b)/1024) }
        return String(format: "%.1f MB", Double(b)/1048576)
    }

    // MARK: Clipboard auto-capture — anything copied anywhere drops into Pano

    func startClipboardWatch() {
        lastChangeCount = NSPasteboard.general.changeCount
        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
    }

    func pollClipboard() {
        let pb = NSPasteboard.general
        if pb.changeCount == lastChangeCount { return }
        lastChangeCount = pb.changeCount
        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let json = jsonString(s) else { return }
        web?.evaluateJavaScript("window.__addClip && window.__addClip(\(json));", completionHandler: nil)
    }

    func applicationWillTerminate(_ note: Notification) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    // MARK: Panel + WebView

    func buildPanel() {
        let defaults = UserDefaults.standard
        let w = CGFloat(defaults.double(forKey: "win_w"))
        let h = CGFloat(defaults.double(forKey: "win_h"))
        let width  = w > 0 ? w : 404
        let height = h > 0 ? h : 486

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(
            x: screen.maxX - width - 44,
            y: screen.maxY - height - 24
        )
        if defaults.object(forKey: "win_x") != nil {
            origin.x = CGFloat(defaults.double(forKey: "win_x"))
            origin.y = CGFloat(defaults.double(forKey: "win_y"))
        }
        let frame = NSRect(origin: origin, size: CGSize(width: width, height: height))

        panel = NotePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "bridge")
        config.userContentController = ucc
        config.websiteDataStore = .default()

        // frosted-glass backdrop (real macOS vibrancy)
        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.material = .underWindowBackground
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        panel.contentView = blur
        noteBlur = blur

        web = WKWebView(frame: blur.bounds, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        // round the web view's own layer — its hosted content layer ignores the
        // ancestor mask, so without this the square corners poke out (white/black corners)
        web.wantsLayer = true
        web.layer?.cornerRadius = 18
        web.layer?.masksToBounds = true
        blur.addSubview(web)

        web.loadHTMLString(htmlString, baseURL: nil)
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Hızlı Not") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "✎"
            }
        }
        let menu = NSMenu()
        let noteItem = menu.addItem(withTitle: "Notu Göster / Gizle  ⌘⇧N", action: #selector(toggle), keyEquivalent: "")
        noteItem.target = self
        let shelfItem = menu.addItem(withTitle: "Rafı Göster (sürüklerken salla)", action: #selector(showShelfMenu), keyEquivalent: "")
        shelfItem.target = self
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: Global hotkey (⌘⇧N) via Carbon — no accessibility permission needed

    func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x484B454E /* 'HKEN' */), id: 1)
        let mods = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), mods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @objc func showShelfMenu() { showShelf() }

    @objc func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        web.evaluateJavaScript("window.__focus && window.__focus();", completionHandler: nil)
    }

    // MARK: Persistence

    func loadState() -> String {
        guard let data = try? Data(contentsOf: stateURL),
              let str = String(data: data, encoding: .utf8) else { return "null" }
        return str
    }

    func saveGeometry() {
        let f = panel.frame
        let d = UserDefaults.standard
        d.set(Double(f.origin.x), forKey: "win_x")
        d.set(Double(f.origin.y), forKey: "win_y")
        d.set(Double(f.size.width), forKey: "win_w")
        d.set(Double(f.size.height), forKey: "win_h")
    }

    // MARK: Live drag / resize driven by JS deltas

    func clampOnScreen() {
        guard let vis = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = panel.frame
        f.origin.x = max(vis.minX + 4, min(f.origin.x, vis.maxX - f.size.width - 4))
        f.origin.y = max(vis.minY + 4, min(f.origin.y, vis.maxY - f.size.height - 4))
        panel.setFrameOrigin(f.origin)
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        var f = panel.frame
        f.origin.x += dx
        f.origin.y -= dy // screen-down means lower Cocoa y
        guard let vis = (panel.screen ?? NSScreen.main)?.visibleFrame else { panel.setFrameOrigin(f.origin); return }
        f.origin.x = max(vis.minX + 4, min(f.origin.x, vis.maxX - f.size.width - 4))
        f.origin.y = max(vis.minY + 4, min(f.origin.y, vis.maxY - f.size.height - 4))
        panel.setFrameOrigin(f.origin)
    }

    func resizeBy(dx: CGFloat, dy: CGFloat, mode: String) {
        var f = panel.frame
        let top = f.origin.y + f.size.height
        let vis = (panel.screen ?? NSScreen.main)?.visibleFrame ?? f
        let maxW = vis.maxX - f.origin.x - 4
        let maxH = top - vis.minY - 4
        if mode.contains("e") { f.size.width  = max(minW, min(f.size.width + dx, maxW)) }
        if mode.contains("s") { f.size.height = max(minH, min(f.size.height + dy, maxH)) }
        f.origin.y = top - f.size.height // keep top edge fixed
        panel.setFrame(f, display: true)
    }

    // MARK: Bridge from JS

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "persist":
            if let state = body["state"],
               let data = try? JSONSerialization.data(withJSONObject: state, options: []) {
                try? data.write(to: stateURL)
            }
        case "move":
            moveBy(dx: cg(body["dx"]), dy: cg(body["dy"]))
        case "resize":
            resizeBy(dx: cg(body["dx"]), dy: cg(body["dy"]), mode: (body["mode"] as? String) ?? "")
        case "geomEnd":
            saveGeometry()
        case "hide":
            panel.orderOut(nil)
        case "readClipboard":
            let s = NSPasteboard.general.string(forType: .string) ?? ""
            if let json = jsonString(s) {
                web.evaluateJavaScript("window.__addClip(\(json));", completionHandler: nil)
            }
        case "writeClipboard":
            let text = (body["text"] as? String) ?? ""
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            lastChangeCount = pb.changeCount // don't re-capture our own write
        case "saveFile":
            if let id = body["id"] as? String, let it = FileStore.shared.item(id) {
                saveFileURL(it.url, name: it.name)
            } else {
                saveFile(name: (body["name"] as? String) ?? "dosya", dataURL: (body["dataUrl"] as? String) ?? "")
            }
        case "addFiles":
            if let arr = body["items"] as? [[String: Any]] {
                for f in arr {
                    let name = (f["name"] as? String) ?? "dosya"
                    guard let dataURL = f["dataUrl"] as? String,
                          let comma = dataURL.range(of: ","),
                          let data = Data(base64Encoded: String(dataURL[comma.upperBound...])) else { continue }
                    FileStore.shared.addData(data, name: name)
                }
            }
        case "removeFile":
            if let id = body["id"] as? String { FileStore.shared.remove(id) }
        case "revealFile":
            if let id = body["id"] as? String, let it = FileStore.shared.item(id) {
                NSWorkspace.shared.activateFileViewerSelecting([it.url])
            }
        case "showShelf":
            showShelf()
        case "filesReady":
            pushFilesToWeb()
        case "appearance":
            applyAppearance(dark: (body["dark"] as? Bool) ?? false)
        case "quit":
            NSApp.terminate(nil)
        case "launchAtLogin":
            setLaunchAtLogin((body["on"] as? Bool) ?? false)
        case "collapse":
            setCollapsed((body["on"] as? Bool) ?? false)
        case "zoom":
            toggleZoom()
        default:
            break
        }
    }

    func applyAppearance(dark: Bool) {
        let ap = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.appearance = ap
        noteBlur?.appearance = ap
        noteBlur?.material = dark ? .hudWindow : .underWindowBackground
    }

    func setLaunchAtLogin(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { NSLog("launchAtLogin error: \(error)") }
        }
    }

    func setCollapsed(_ on: Bool) {
        var f = panel.frame
        let top = f.origin.y + f.size.height
        if on {
            preCollapseHeight = f.size.height
            f.size.height = 46
        } else {
            f.size.height = preCollapseHeight ?? 486
            preCollapseHeight = nil
        }
        f.origin.y = top - f.size.height
        panel.setFrame(f, display: true, animate: true)
        saveGeometry()
    }

    func toggleZoom() {
        let vis = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        if let pre = preZoomFrame {
            panel.setFrame(pre, display: true, animate: true)
            preZoomFrame = nil
        } else {
            preZoomFrame = panel.frame
            let w = min(760, vis.width - 80)
            let h = min(860, vis.height - 80)
            let top = panel.frame.origin.y + panel.frame.size.height
            var f = NSRect(x: panel.frame.origin.x, y: top - h, width: w, height: h)
            f.origin.x = min(max(f.origin.x, vis.minX + 8), vis.maxX - w - 8)
            f.origin.y = min(max(f.origin.y, vis.minY + 8), vis.maxY - h - 8)
            panel.setFrame(f, display: true, animate: true)
        }
        saveGeometry()
    }

    func saveFileURL(_ url: URL, name: String) {
        let save = NSSavePanel()
        save.nameFieldStringValue = name
        save.canCreateDirectories = true
        save.level = .modalPanel
        if save.runModal() == .OK, let dest = save.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }

    func cg(_ any: Any?) -> CGFloat {
        if let d = any as? Double { return CGFloat(d) }
        if let i = any as? Int { return CGFloat(i) }
        if let n = any as? NSNumber { return CGFloat(n.doubleValue) }
        return 0
    }

    func jsonString(_ s: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
              let str = String(data: data, encoding: .utf8) else { return nil }
        // wrap/unwrap the single-element array to get a safely-escaped JS string literal
        return String(str.dropFirst().dropLast())
    }

    func saveFile(name: String, dataURL: String) {
        guard let comma = dataURL.range(of: ",") else { return }
        let b64 = String(dataURL[comma.upperBound...])
        guard let data = Data(base64Encoded: b64) else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = name
        save.canCreateDirectories = true
        save.level = .modalPanel
        if save.runModal() == .OK, let url = save.url {
            try? data.write(to: url)
        }
    }

    // MARK: WebView delegates

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let json = loadState()
        webView.evaluateJavaScript("window.__bootstrap && window.__bootstrap(\(json));", completionHandler: nil)
    }

    // Support <input type="file"> native open panel
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.canChooseFiles = true
        open.canChooseDirectories = false
        open.level = .modalPanel
        completionHandler(open.runModal() == .OK ? open.urls : nil)
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
