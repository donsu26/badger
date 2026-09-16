// Persistent menu bar icon for Badger.
//
// Draws the badger mark as an NSStatusItem template image (macOS tints it
// automatically for light/dark menu bars), and shows today's checklist
// status in the dropdown, refreshed from `badger status --json` each time
// the menu opens. Unlike the overlay/calendar-events binaries, this process
// is meant to run continuously for the whole login session.
import Cocoa

let badgerDir = FileManager.default.currentDirectoryPath
let badgerCLI = badgerDir + "/bin/badger"

func runBadgerCLI(_ args: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: badgerCLI)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func makeStatusBarIcon(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.saveGState()
        ctx.scaleBy(x: rect.width / 512.0, y: rect.height / 512.0)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        // ears
        ctx.fillEllipse(in: CGRect(x: 172 - 54, y: 128 - 54, width: 108, height: 108))
        ctx.fillEllipse(in: CGRect(x: 340 - 54, y: 128 - 54, width: 108, height: 108))

        // head outline (transparent center - only the outline is opaque)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 256, y: 120))
        head.addCurve(to: CGPoint(x: 400, y: 270), control1: CGPoint(x: 350, y: 120), control2: CGPoint(x: 400, y: 180))
        head.addCurve(to: CGPoint(x: 256, y: 455), control1: CGPoint(x: 400, y: 360), control2: CGPoint(x: 340, y: 430))
        head.addCurve(to: CGPoint(x: 112, y: 270), control1: CGPoint(x: 172, y: 430), control2: CGPoint(x: 112, y: 360))
        head.addCurve(to: CGPoint(x: 256, y: 120), control1: CGPoint(x: 112, y: 180), control2: CGPoint(x: 162, y: 120))
        head.closeSubpath()
        ctx.setLineWidth(16)
        ctx.addPath(head)
        ctx.strokePath()

        // left stripe (nose to ear)
        let leftStripe = CGMutablePath()
        leftStripe.move(to: CGPoint(x: 256, y: 442))
        leftStripe.addQuadCurve(to: CGPoint(x: 185, y: 370), control: CGPoint(x: 200, y: 430))
        leftStripe.addQuadCurve(to: CGPoint(x: 188, y: 230), control: CGPoint(x: 168, y: 300))
        leftStripe.addQuadCurve(to: CGPoint(x: 225, y: 155), control: CGPoint(x: 205, y: 175))
        leftStripe.addQuadCurve(to: CGPoint(x: 250, y: 165), control: CGPoint(x: 245, y: 145))
        leftStripe.addQuadCurve(to: CGPoint(x: 240, y: 230), control: CGPoint(x: 255, y: 190))
        leftStripe.addQuadCurve(to: CGPoint(x: 232, y: 340), control: CGPoint(x: 225, y: 280))
        leftStripe.addQuadCurve(to: CGPoint(x: 256, y: 442), control: CGPoint(x: 238, y: 390))
        leftStripe.closeSubpath()
        ctx.addPath(leftStripe)
        ctx.fillPath()

        // right stripe (mirror of left, x -> 512 - x)
        let rightStripe = CGMutablePath()
        rightStripe.move(to: CGPoint(x: 256, y: 442))
        rightStripe.addQuadCurve(to: CGPoint(x: 327, y: 370), control: CGPoint(x: 312, y: 430))
        rightStripe.addQuadCurve(to: CGPoint(x: 324, y: 230), control: CGPoint(x: 344, y: 300))
        rightStripe.addQuadCurve(to: CGPoint(x: 287, y: 155), control: CGPoint(x: 307, y: 175))
        rightStripe.addQuadCurve(to: CGPoint(x: 262, y: 165), control: CGPoint(x: 267, y: 145))
        rightStripe.addQuadCurve(to: CGPoint(x: 272, y: 230), control: CGPoint(x: 257, y: 190))
        rightStripe.addQuadCurve(to: CGPoint(x: 280, y: 340), control: CGPoint(x: 287, y: 280))
        rightStripe.addQuadCurve(to: CGPoint(x: 256, y: 442), control: CGPoint(x: 274, y: 390))
        rightStripe.closeSubpath()
        ctx.addPath(rightStripe)
        ctx.fillPath()

        // nose
        ctx.fillEllipse(in: CGRect(x: 256 - 24, y: 452 - 17, width: 48, height: 34))

        // eyes
        ctx.fillEllipse(in: CGRect(x: 214 - 10, y: 290 - 10, width: 20, height: 20))
        ctx.fillEllipse(in: CGRect(x: 298 - 10, y: 290 - 10, width: 20, height: 20))

        ctx.restoreGState()
        return true
    }
    image.isTemplate = true
    return image
}

struct StatusItemRow: Decodable {
    let name: String
    let status: String
    let detail: String
}

struct StatusPayload: Decodable {
    let items: [StatusItemRow]
    let paused: Bool
}

final class StatusBarController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var refreshTimer: Timer?

    func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem.button?.image = makeStatusBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let menu = self.statusItem.menu else { return }
            self.rebuildMenu(menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let output = runBadgerCLI(["status", "--json"])
        let payload = try? JSONDecoder().decode(StatusPayload.self, from: Data(output.utf8))

        let header = NSMenuItem(title: "Today", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let payload, !payload.items.isEmpty {
            for row in payload.items {
                let item = NSMenuItem(title: "\(row.name) — \(row.detail)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.image = dot(for: row.status)
                menu.addItem(item)
            }
        } else {
            let empty = NSMenuItem(title: "(no items configured)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())

        let history = NSMenuItem(title: "Open History…", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let isPaused = payload?.paused ?? false
        let pause = NSMenuItem(
            title: isPaused ? "Resume Reminders" : "Pause Reminders",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        pause.representedObject = isPaused
        menu.addItem(pause)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Badger", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    func dot(for status: String) -> NSImage {
        let color: NSColor
        switch status {
        case "done": color = .systemGreen
        case "pending": color = .systemYellow
        default: color = .tertiaryLabelColor  // skipped, missed
        }
        let size: CGFloat = 8
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image
    }

    @objc func openHistory() {
        let script = "tell application \"Terminal\" to do script \"cd \(badgerDir.replacingOccurrences(of: "\"", with: "\\\"")) && bin/badger history\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    @objc func togglePause(_ sender: NSMenuItem) {
        let wasPaused = (sender.representedObject as? Bool) ?? false
        _ = runBadgerCLI([wasPaused ? "resume" : "pause"])
        if let menu = statusItem.menu {
            rebuildMenu(menu)
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let controller = StatusBarController()
controller.start()
NSApplication.shared.run()
