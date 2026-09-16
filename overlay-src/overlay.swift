// Full-screen blurred reminder overlay for Badger.
//
// Usage:
//   overlay "<item name>" <giving_up_after_seconds>
//   overlay --meeting "<title>" "<joinUrl-or-empty>" <giving_up_after_seconds>
// Checklist mode prints exactly one of: done | skip | timeout, then exits.
// Meeting mode prints exactly one of: join | dismiss | timeout, then exits.
//
// This is a compiled Swift binary (not a script run via osascript) because a
// manually-driven NSApplication invoked through `osascript -l JavaScript`
// could display windows but never actually became the key/active app, so
// real mouse clicks on the buttons were silently swallowed as mere
// focus-steal attempts. A compiled process running a real `NSApp.run()`
// event loop becomes key/main/active correctly (verified directly).
import Cocoa

let args = CommandLine.arguments
let isMeeting = args.count > 1 && args[1] == "--meeting"

let itemName: String
let givingUpAfter: Double
let meetingJoinURL: String?

if isMeeting {
    itemName = args.count > 2 ? args[2] : "Meeting"
    let rawJoinURL = args.count > 3 ? args[3] : ""
    meetingJoinURL = rawJoinURL.isEmpty ? nil : rawJoinURL
    givingUpAfter = args.count > 4 ? (Double(args[4]) ?? 90) : 90
} else {
    itemName = args.count > 1 ? args[1] : "Reminder"
    meetingJoinURL = nil
    givingUpAfter = args.count > 2 ? (Double(args[2]) ?? 50) : 50
}

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayController: NSObject {
    var windows: [NSWindow] = []
    var timeoutTimer: Timer?

    func build() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false

            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            window.contentView = effect

            if screen === activeScreen {
                addControls(to: effect)
            }

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        app.activate(ignoringOtherApps: true)

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: givingUpAfter, repeats: false) { [weak self] _ in
            self?.finish(with: "timeout")
        }

        if let selfTest = ProcessInfo.processInfo.environment["BADGER_OVERLAY_SELF_TEST"] {
            scheduleSelfTest(selfTest)
        }
    }

    var doneButton: NSButton?
    var skipButton: NSButton?
    var joinButton: NSButton?
    var dismissButton: NSButton?

    func addControls(to effect: NSVisualEffectView) {
        if isMeeting {
            addMeetingControls(to: effect)
        } else {
            addChecklistControls(to: effect)
        }
    }

    func addChecklistControls(to effect: NSVisualEffectView) {
        let label = NSTextField(labelWithString: "Reminder: \(itemName)")
        label.font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        let done = NSButton(title: "Done for today", target: self, action: #selector(onDone))
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(done)
        doneButton = done

        let skip = NSButton(title: "Skip today", target: self, action: #selector(onSkip))
        skip.bezelStyle = .rounded
        skip.controlSize = .large
        skip.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(skip)
        skipButton = skip

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -80),

            done.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 20),
            done.trailingAnchor.constraint(equalTo: effect.centerXAnchor, constant: -10),
            done.widthAnchor.constraint(equalToConstant: 180),

            skip.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 20),
            skip.leadingAnchor.constraint(equalTo: effect.centerXAnchor, constant: 10),
            skip.widthAnchor.constraint(equalToConstant: 180),
        ])
    }

    func addMeetingControls(to effect: NSVisualEffectView) {
        let label = NSTextField(labelWithString: "Starting soon: \(itemName)")
        label.font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        let dismiss = NSButton(title: "Dismiss", target: self, action: #selector(onDismiss))
        dismiss.bezelStyle = .rounded
        dismiss.controlSize = .large
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dismiss)
        dismissButton = dismiss

        if meetingJoinURL != nil {
            let join = NSButton(title: "Join Meeting", target: self, action: #selector(onJoin))
            join.bezelStyle = .rounded
            join.controlSize = .large
            join.keyEquivalent = "\r"
            join.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(join)
            joinButton = join

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -80),

                join.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 20),
                join.trailingAnchor.constraint(equalTo: effect.centerXAnchor, constant: -10),
                join.widthAnchor.constraint(equalToConstant: 180),

                dismiss.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 20),
                dismiss.leadingAnchor.constraint(equalTo: effect.centerXAnchor, constant: 10),
                dismiss.widthAnchor.constraint(equalToConstant: 180),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -80),

                dismiss.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
                dismiss.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 20),
                dismiss.widthAnchor.constraint(equalToConstant: 180),
            ])
        }
    }

    func scheduleSelfTest(_ mode: String) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            switch mode {
            case "done": self.doneButton?.performClick(nil)
            case "skip": self.skipButton?.performClick(nil)
            case "join": self.joinButton?.performClick(nil)
            case "dismiss": self.dismissButton?.performClick(nil)
            default: break
            }
        }
    }

    @objc func onDone() { finish(with: "done") }
    @objc func onSkip() { finish(with: "skip") }

    @objc func onJoin() {
        if let urlString = meetingJoinURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        finish(with: "join")
    }

    @objc func onDismiss() { finish(with: "dismiss") }

    func finish(with value: String) {
        timeoutTimer?.invalidate()
        for window in windows { window.orderOut(nil) }
        print(value)
        exit(0)
    }
}

let controller = OverlayController()
controller.build()
NSApplication.shared.run()
