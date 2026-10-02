import AppKit
import ServiceManagement

// MiniQuit — tiny Sermo-style menu-bar force-quit list.
// Menu icon is the Sermo "S" mark redrawn in code on a transparent background.
// Card is a small dark popover: app icon + name per row, hung apps on top.

// ponytail: single-file AppKit status item; no SwiftUI/Xcode project, no deps.

let periwinkle = NSColor(srgbRed: 0x8B/255.0, green: 0x9C/255.0, blue: 0xFF/255.0, alpha: 1.0)
let cardBg = NSColor(srgbRed: 0x0F/255.0, green: 0x16/255.0, blue: 0x23/255.0, alpha: 1.0)
let lime = NSColor(srgbRed: 0xC6/255.0, green: 0xFF/255.0, blue: 0x4A/255.0, alpha: 1.0)

// Sermo "S" mark drawn into a 20 x 18 design box: two fat rounded strokes.
// Top: green -> blue rising to the right. Bottom: blue -> yellow -> red falling right.
// ponytail: scale/origin are baked into the coordinates, never the CTM — a scaleBy
// before replacePathWithStrokedPath() silently drops the round line caps.
func drawMark(_ ctx: CGContext, scale: CGFloat = 1, origin: CGPoint = .zero) {
    ctx.beginPath()
    func capsule(from a: CGPoint, to b: CGPoint, width: CGFloat,
                 stops: [(CGFloat, NSColor)]) {
        let p0 = CGPoint(x: origin.x + a.x * scale, y: origin.y + a.y * scale)
        let p1 = CGPoint(x: origin.x + b.x * scale, y: origin.y + b.y * scale)
        ctx.saveGState()
        ctx.setLineWidth(width * scale)
        ctx.setLineCap(.round)
        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let colors = stops.map { $0.1.cgColor } as CFArray
        let locs = stops.map { $0.0 }
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: locs) {
            // Without these two flags CG only paints the strip between p0 and p1,
            // which slices the round caps off and makes the strokes look square.
            ctx.drawLinearGradient(g, start: p0, end: p1,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }
    capsule(from: CGPoint(x: 6.5, y: 10.0), to: CGPoint(x: 15.5, y: 13.5), width: 5.6, stops: [
        (0.0, NSColor(srgbRed: 0x35/255.0, green: 0xC2/255.0, blue: 0x6E/255.0, alpha: 1.0)),
        (0.55, NSColor(srgbRed: 0x2E/255.0, green: 0xAF/255.0, blue: 0xB8/255.0, alpha: 1.0)),
        (1.0, NSColor(srgbRed: 0x2E/255.0, green: 0x9B/255.0, blue: 0xFF/255.0, alpha: 1.0)),
    ])
    capsule(from: CGPoint(x: 4.5, y: 7.0), to: CGPoint(x: 15.0, y: 3.0), width: 5.6, stops: [
        (0.0, NSColor(srgbRed: 0x2E/255.0, green: 0x7C/255.0, blue: 0xF6/255.0, alpha: 1.0)),
        (0.55, NSColor(srgbRed: 0xFF/255.0, green: 0xC5/255.0, blue: 0x31/255.0, alpha: 1.0)),
        (1.0, NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x2E/255.0, alpha: 1.0)),
    ])
}

func pillIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 20, height: 18))
    img.isTemplate = false
    img.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext { drawMark(ctx) }
    img.unlockFocus()
    return img
}

// Finder/Launchpad icon: dark rounded tile + the same mark, rendered natively at `size`.
func appIconImage(_ size: CGFloat) -> NSImage {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size),
                                     pixelsHigh: Int(size), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0),
          let gc = NSGraphicsContext(bitmapImageRep: rep) else {
        return NSImage(size: NSSize(width: size, height: size))
    }
    rep.size = NSSize(width: size, height: size)
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = gc
    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                            xRadius: size * 0.2237, yRadius: size * 0.2237)
    NSGradient(colors: [
        NSColor(srgbRed: 0x1B/255.0, green: 0x25/255.0, blue: 0x40/255.0, alpha: 1.0),
        cardBg,
    ])!.draw(in: tile, angle: -90)
    let ctx = gc.cgContext
    // Centre the mark's visual bbox (design x 1.7…18.3, y 0.2…16.3) in the tile.
    let s = size * 0.62 / 16.6
    drawMark(ctx, scale: s, origin: CGPoint(x: (size - 16.6 * s) / 2 - 1.7 * s,
                                            y: (size - 16.1 * s) / 2 - 0.2 * s))
    gc.flushGraphics()
    NSGraphicsContext.current = prev
    let img = NSImage(size: NSSize(width: size, height: size))
    img.addRepresentation(rep)
    return img
}

struct AppRow {
    let app: NSRunningApplication
    let name: String
    let icon: NSImage
    let pid: pid_t
    let unresponsive: Bool
}

func fetchApps() -> [AppRow] {
    let me = ProcessInfo.processInfo.processIdentifier
    let ws = NSWorkspace.shared
    var rows: [AppRow] = []
    for a in ws.runningApplications {
        guard a.activationPolicy == .regular else { continue }
        guard a.processIdentifier != me else { continue }
        guard let name = a.localizedName, !name.isEmpty else { continue }
        // ponytail: private KVC isUnresponsive is what Finder uses; fallback = responsive.
        let stuck = (a.value(forKey: "isUnresponsive") as? Bool) ?? false
        rows.append(AppRow(app: a, name: name, icon: a.icon ?? NSImage(), pid: a.processIdentifier, unresponsive: stuck))
    }
    // Crashed/hung first, then A–Z — the hung case surfaces at top.
    return rows.sorted {
        if $0.unresponsive != $1.unresponsive { return $0.unresponsive && !$1.unresponsive }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
}

final class ListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [AppRow] = []
    let table = NSTableView()
    let scroll = NSScrollView()
    let quitBtn = NSButton(title: "Force Quit", target: nil, action: nil)
    let statusLbl = NSTextField(labelWithString: "")
    var timer: Timer?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 300))
        v.wantsLayer = true
        v.layer?.backgroundColor = cardBg.cgColor
        v.layer?.cornerRadius = 12
        self.view = v

        let title = NSTextField(labelWithString: "Force Quit")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title)

        let hint = NSTextField(labelWithString: "Hung apps rise to the top.")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = NSColor(white: 1, alpha: 0.55)
        hint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(hint)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.width = 234
        table.addTableColumn(col)
        table.delegate = self
        table.dataSource = self
        table.headerView = nil
        table.backgroundColor = .clear
        table.appearance = NSAppearance(named: .darkAqua)
        table.target = self
        table.doubleAction = #selector(forceQuitSelected)
        table.rowHeight = 28
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.backgroundColor = .clear
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scroll)

        statusLbl.font = NSFont.systemFont(ofSize: 10)
        statusLbl.textColor = NSColor(white: 1, alpha: 0.55)
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(statusLbl)

        quitBtn.target = self
        quitBtn.action = #selector(forceQuitSelected)
        quitBtn.bezelStyle = .rounded
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(quitBtn)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: statusLbl.topAnchor, constant: -6),
            statusLbl.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            statusLbl.trailingAnchor.constraint(lessThanOrEqualTo: quitBtn.leadingAnchor, constant: -8),
            statusLbl.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -10),
            quitBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10),
            quitBtn.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
            quitBtn.widthAnchor.constraint(equalToConstant: 96),
        ])
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh(keepSelection: true) }
    }

    func refresh(keepSelection: Bool = false) {
        let sel: pid_t? = keepSelection ? selectedRow()?.pid : nil
        rows = fetchApps()
        table.reloadData()
        if let s = sel, let i = rows.firstIndex(where: { $0.pid == s }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
        updateFooter()
    }

    func selectedRow() -> AppRow? {
        let i = table.selectedRow
        guard i >= 0, i < rows.count else { return nil }
        return rows[i]
    }

    func updateFooter() {
        if let s = selectedRow() {
            statusLbl.stringValue = s.unresponsive ? "\(s.name) — not responding" : s.name
            quitBtn.isEnabled = true
        } else {
            statusLbl.stringValue = rows.isEmpty ? "All clear — nothing hung." : "\(rows.count) apps"
            quitBtn.isEnabled = false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = rows[row]
        let cellID = NSUserInterfaceItemIdentifier("cell")
        var cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellID
            let iv = NSImageView(frame: NSRect(x: 0, y: 6, width: 16, height: 16))
            iv.identifier = NSUserInterfaceItemIdentifier("icon")
            cell?.addSubview(iv)
            let tf = NSTextField(labelWithString: "")
            tf.identifier = NSUserInterfaceItemIdentifier("name")
            tf.font = NSFont.systemFont(ofSize: 12)
            tf.textColor = .white
            tf.backgroundColor = .clear
            tf.isBordered = false
            cell?.textField = tf
            cell?.addSubview(tf)
            let badge = NSTextField(labelWithString: "")
            badge.identifier = NSUserInterfaceItemIdentifier("badge")
            badge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            badge.textColor = lime
            badge.backgroundColor = .clear
            badge.isBordered = false
            cell?.addSubview(badge)
            // Layout by frame (tiny card, avoids constraints per row)
            iv.frame = NSRect(x: 4, y: 6, width: 16, height: 16)
            tf.frame = NSRect(x: 26, y: 5, width: 130, height: 18)
            badge.frame = NSRect(x: 158, y: 6, width: 72, height: 15)
        }
        func sub(_ id: String) -> NSView? {
            cell?.subviews.first(where: { $0.identifier?.rawValue == id })
        }
        (sub("icon") as? NSImageView)?.image = r.icon
        // Running + responsive shows NO badge; hung shows it.
        (cell?.textField)?.stringValue = r.name
        (sub("badge") as? NSTextField)?.stringValue = r.unresponsive ? "● Not running" : ""
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateFooter() }

    @objc func forceQuitSelected() {
        guard let s = selectedRow() else { return }
        // forceTerminate returns false if it needs the kill fallback.
        if !s.app.forceTerminate() {
            kill(s.pid, SIGKILL)
        }
        statusLbl.stringValue = "Quitting \(s.name)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var popover = NSPopover()
    var list = ListController()

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = pillIcon()
        item.button?.toolTip = "MiniQuit — force quit hung apps"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.contentViewController = list
        popover.behavior = .transient
        popover.animates = true
        // --show: pop the card open on launch so first run is visible at once.
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.toggle() }
        }
        // Self-heal the login item: only register when not already there.
        if #available(macOS 13.0, *) {
            let svc = SMAppService.mainApp
            if svc.status == .notRegistered { try? svc.register() }
        }
    }

    @objc func toggle() {
        guard let btn = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        list.refresh()
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
    }
}

// Build-time / diagnostic CLI flags — handled before the run loop.
if let i = CommandLine.arguments.firstIndex(of: "--genicon"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    let img = appIconImage(1024)
    let png = img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
        .representation(using: .png, properties: [:])
    guard let png, (try? png.write(to: URL(fileURLWithPath: path))) != nil else { exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--login-status") {
    if #available(macOS 13.0, *) {
        let s = SMAppService.mainApp.status
        print("SMAppService status = \(s.rawValue) (0 notRegistered, 1 enabled, 2 requiresApproval, 3 notFound)")
    } else {
        print("macOS < 13")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = AppDelegate()
app.delegate = del
app.run()
