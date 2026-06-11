import Cocoa
import UniformTypeIdentifiers

// MARK: - File model + shared store (on-disk so native drag-out gives real files)

final class FileItem {
    let id: String
    let url: URL
    let name: String
    let size: Int
    let isImage: Bool
    private var cachedThumb: String?

    init(id: String, url: URL, name: String, size: Int) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        let ext = (name as NSString).pathExtension.lowercased()
        self.isImage = ["png","jpg","jpeg","gif","heic","webp","bmp","tiff","tif"].contains(ext)
    }

    var ext: String {
        let e = (name as NSString).pathExtension
        return e.isEmpty ? "DOSYA" : String(e.prefix(4)).uppercased()
    }

    func icon(_ side: CGFloat) -> NSImage {
        if isImage, let img = NSImage(contentsOf: url) { return img }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: side, height: side)
        return icon
    }

    // small base64 PNG thumbnail for the web "Dosyalar" mirror
    func thumbDataURL() -> String {
        if let c = cachedThumb { return c }
        guard isImage, let img = NSImage(contentsOf: url) else { cachedThumb = ""; return "" }
        let target = NSSize(width: 120, height: 120)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep = rep else { cachedThumb = ""; return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // aspect-fill
        let s = img.size
        let scale = max(target.width / max(s.width,1), target.height / max(s.height,1))
        let dw = s.width * scale, dh = s.height * scale
        img.draw(in: NSRect(x: (target.width-dw)/2, y: (target.height-dh)/2, width: dw, height: dh))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { cachedThumb = ""; return "" }
        let out = "data:image/png;base64," + data.base64EncodedString()
        cachedThumb = out
        return out
    }
}

final class FileStore {
    static let shared = FileStore()
    private(set) var items: [FileItem] = []
    var onChange: (() -> Void)?
    let dir: URL

    init() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HizliNotShelf-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func uniqueDest(_ name: String) -> URL {
        var dest = dir.appendingPathComponent(name)
        var i = 1
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            let n = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = dir.appendingPathComponent(n)
            i += 1
        }
        return dest
    }

    private func uid() -> String { "f" + UUID().uuidString.prefix(8) }

    @discardableResult
    func addURLs(_ urls: [URL]) -> Bool {
        var added = false
        for u in urls {
            let name = u.lastPathComponent
            let dest = uniqueDest(name)
            do {
                try FileManager.default.copyItem(at: u, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? Int) ?? 0
                items.insert(FileItem(id: uid(), url: dest, name: dest.lastPathComponent, size: size), at: 0)
                added = true
            } catch {}
        }
        if added { changed() }
        return added
    }

    func addData(_ data: Data, name: String) {
        let dest = uniqueDest(name)
        do {
            try data.write(to: dest)
            items.insert(FileItem(id: uid(), url: dest, name: dest.lastPathComponent, size: data.count), at: 0)
            changed()
        } catch {}
    }

    func remove(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: items[idx].url)
        items.remove(at: idx)
        changed()
    }

    func clear() {
        for it in items { try? FileManager.default.removeItem(at: it.url) }
        items.removeAll()
        changed()
    }

    func item(_ id: String) -> FileItem? { items.first { $0.id == id } }
    private func changed() { onChange?() }
}

// MARK: - Shake detector (works during any drag, incl. dragging a file from Finder)

final class ShakeMonitor {
    var onShake: (() -> Void)?
    private var globalMon: Any?
    private var localMon: Any?
    private var xs: [(t: TimeInterval, x: CGFloat)] = []
    private var lastFire: TimeInterval = 0

    func start() {
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in self?.handle() }
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in self?.handle(); return e }
    }

    private func handle() {
        let now = ProcessInfo.processInfo.systemUptime
        let x = NSEvent.mouseLocation.x
        xs.append((now, x))
        xs = xs.filter { now - $0.t < 0.5 }
        guard xs.count >= 6 else { return }

        var reversals = 0
        var lastSign = 0
        var minX = xs[0].x, maxX = xs[0].x
        for i in 1..<xs.count {
            let dx = xs[i].x - xs[i-1].x
            minX = min(minX, xs[i].x); maxX = max(maxX, xs[i].x)
            if abs(dx) < 2 { continue }
            let sign = dx > 0 ? 1 : -1
            if lastSign != 0 && sign != lastSign { reversals += 1 }
            lastSign = sign
        }
        if reversals >= 4 && (maxX - minX) > 90 && now - lastFire > 1.2 {
            lastFire = now
            xs.removeAll()
            onShake?()
        }
    }
}

// MARK: - A draggable file chip (native drag-OUT to Finder / other apps)

final class ChipView: NSView, NSDraggingSource {
    let item: FileItem
    var onRemove: ((String) -> Void)?
    private var down = NSPoint.zero
    private let thumb = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let removeBtn = NSButton()

    init(item: FileItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 84))
        wantsLayer = true

        thumb.frame = NSRect(x: 6, y: 30, width: 52, height: 52)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 9
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        thumb.image = item.icon(52)
        if !item.isImage {
            thumb.layer?.borderWidth = 0.5
            thumb.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        }
        addSubview(thumb)

        label.frame = NSRect(x: 0, y: 8, width: 64, height: 16)
        label.alignment = .center
        label.font = .systemFont(ofSize: 10)
        label.textColor = NSColor(white: 1, alpha: 0.8)
        label.lineBreakMode = .byTruncatingMiddle
        label.stringValue = item.name
        label.toolTip = item.name
        addSubview(label)

        removeBtn.frame = NSRect(x: 46, y: 64, width: 18, height: 18)
        removeBtn.isBordered = false
        removeBtn.title = "✕"
        removeBtn.font = .systemFont(ofSize: 10)
        removeBtn.contentTintColor = NSColor(white: 1, alpha: 0.85)
        removeBtn.wantsLayer = true
        removeBtn.layer?.cornerRadius = 9
        removeBtn.layer?.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        removeBtn.target = self
        removeBtn.action = #selector(removeTapped)
        removeBtn.isHidden = true
        addSubview(removeBtn)

        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        toolTip = "Finder’a ya da başka uygulamaya sürükle"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { removeBtn.isHidden = false }
    override func mouseExited(with event: NSEvent) { removeBtn.isHidden = true }
    @objc private func removeTapped() { onRemove?(item.id) }

    override func mouseDown(with event: NSEvent) { down = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        if abs(p.x - down.x) < 4 && abs(p.y - down.y) < 4 { return }
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let img = item.icon(52)
        dragItem.setDraggingFrame(thumb.frame, contents: img)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    }
}

// MARK: - Shelf content (drop destination + chip layout)

final class ShelfView: NSView {
    var onChanged: (() -> Void)?
    var onClose: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "Raf")
    private let countLabel = NSTextField(labelWithString: "")
    private let clearBtn = NSButton()
    private let closeBtn = NSButton()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var chips: [ChipView] = []
    private var dragHL = false

    override var isFlipped: Bool { true }

    let chipW: CGFloat = 64, chipH: CGFloat = 84, gap: CGFloat = 8, pad: CGFloat = 12, headerH: CGFloat = 30

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        wantsLayer = true
        registerForDraggedTypes([.fileURL])

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.95)
        addSubview(titleLabel)

        countLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        countLabel.textColor = NSColor(white: 1, alpha: 0.5)
        addSubview(countLabel)

        clearBtn.isBordered = false
        clearBtn.title = "Temizle"
        clearBtn.font = .systemFont(ofSize: 11)
        clearBtn.contentTintColor = NSColor(white: 1, alpha: 0.7)
        clearBtn.target = self
        clearBtn.action = #selector(clearTapped)
        addSubview(clearBtn)

        closeBtn.isBordered = false
        closeBtn.title = "✕"
        closeBtn.font = .systemFont(ofSize: 12)
        closeBtn.contentTintColor = NSColor(white: 1, alpha: 0.6)
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        addSubview(closeBtn)

        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = NSColor(white: 1, alpha: 0.45)
        hint.stringValue = "Dosyaları buraya bırak\nsürüklerken salla → raf gelir"
        hint.maximumNumberOfLines = 2
        addSubview(hint)

        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clearTapped() { FileStore.shared.clear() }
    @objc private func closeTapped() { onClose?() }

    func rebuild() {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        for it in FileStore.shared.items {
            let c = ChipView(item: it)
            c.onRemove = { FileStore.shared.remove($0) }
            addSubview(c)
            chips.append(c)
        }
        countLabel.stringValue = FileStore.shared.items.isEmpty ? "" : "\(FileStore.shared.items.count) öğe"
        hint.isHidden = !FileStore.shared.items.isEmpty
        clearBtn.isHidden = FileStore.shared.items.isEmpty
        needsLayout = true
        onChanged?()
    }

    func cols(forWidth w: CGFloat) -> Int {
        max(1, Int((w - pad*2 + gap) / (chipW + gap)))
    }
    func desiredHeight(forWidth w: CGFloat) -> CGFloat {
        let n = FileStore.shared.items.count
        if n == 0 { return headerH + 64 }
        let c = cols(forWidth: w)
        let rows = (n + c - 1) / c
        return headerH + pad + CGFloat(rows) * (chipH + gap) - gap + pad
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        titleLabel.frame = NSRect(x: pad, y: 8, width: 120, height: 18)
        countLabel.sizeToFit()
        clearBtn.sizeToFit()
        closeBtn.frame = NSRect(x: w - 22 - pad + 4, y: 6, width: 20, height: 20)
        clearBtn.frame = NSRect(x: w - clearBtn.frame.width - 22 - pad - 4, y: 6, width: clearBtn.frame.width, height: 20)
        countLabel.frame = NSRect(x: clearBtn.frame.minX - countLabel.frame.width - 10, y: 8, width: countLabel.frame.width, height: 16)

        if chips.isEmpty {
            hint.frame = NSRect(x: pad, y: headerH + 8, width: w - pad*2, height: 40)
            return
        }
        let c = cols(forWidth: w)
        for (i, chip) in chips.enumerated() {
            let row = i / c, col = i % c
            let x = pad + CGFloat(col) * (chipW + gap)
            let y = headerH + pad + CGFloat(row) * (chipH + gap)
            chip.frame = NSRect(x: x, y: y, width: chipW, height: chipH)
        }
    }

    // drag destination
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragHL = true; needsDisplay = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragHL = false; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { dragHL = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragHL = false; needsDisplay = true
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty else { return false }
        return FileStore.shared.addURLs(urls)
    }

    override func draw(_ dirtyRect: NSRect) {
        if dragHL {
            let r = bounds.insetBy(dx: 6, dy: 6)
            let p = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
            NSColor(white: 1, alpha: 0.07).setFill(); p.fill()
            NSColor(white: 1, alpha: 0.5).setStroke()
            p.lineWidth = 2; p.setLineDash([6, 4], count: 2, phase: 0); p.stroke()
        }
    }
}

// MARK: - Shelf window (aesthetic HUD; pops up near cursor on shake)

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    let shelf = ShelfView()
    private let blur = NSVisualEffectView()
    private var hideTimer: Timer?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        contentView = blur

        shelf.frame = blur.bounds
        shelf.autoresizingMask = [.width, .height]
        blur.addSubview(shelf)

        shelf.onChanged = { [weak self] in self?.resizeToFit() }
        shelf.onClose = { [weak self] in self?.orderOut(nil) }
    }

    func resizeToFit() {
        let w = frame.width
        let h = shelf.desiredHeight(forWidth: w)
        let top = frame.origin.y + frame.height
        var f = frame
        f.size.height = min(max(h, 110), 420)
        f.origin.y = top - f.size.height
        setFrame(f, display: true, animate: false)
    }

    func refresh() { shelf.rebuild(); resizeToFit() }

    func showNear(_ p: NSPoint) {
        refresh()
        let scr = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var f = frame
        f.origin.x = min(max(p.x - f.width/2, scr.minX + 8), scr.maxX - f.width - 8)
        f.origin.y = min(max(p.y - f.height - 22, scr.minY + 8), scr.maxY - f.height - 8)
        setFrame(f, display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func toggleNear(_ p: NSPoint) {
        if isVisible { orderOut(nil) } else { showNear(p) }
    }
}
