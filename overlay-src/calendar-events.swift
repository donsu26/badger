// EventKit CLI for Local Nagger's meeting-reminder feature.
//
// Usage:
//   calendar-events check-auth
//   calendar-events request-access [--timeout <seconds>]
//   calendar-events query --minutes <N>
//
// Every subcommand prints exactly one JSON object to stdout and exits 0,
// even on error - the Python side never has to guess from exit codes or
// crashes. `query` never triggers the macOS permission prompt itself (it
// just reports authorized:false); only `request-access` does that, and it's
// only ever invoked in the foreground (setup.sh or a manual command), never
// from the background 60s tick - otherwise a not-yet-answered prompt would
// re-appear on every tick.
import EventKit
import Foundation

func printJSON(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func statusString(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    @unknown default: return "unknown"
    }
}

func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
    status == .fullAccess
}

let args = CommandLine.arguments
guard args.count > 1 else {
    printJSON(["error": "usage: calendar-events check-auth|request-access|query"])
    exit(0)
}

let command = args[1]
let store = EKEventStore()

switch command {
case "check-auth":
    let status = EKEventStore.authorizationStatus(for: .event)
    printJSON(["authorized": isAuthorized(status), "status": statusString(status)])

case "request-access":
    var timeout: Double = 60
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count {
        timeout = Double(args[idx + 1]) ?? 60
    }

    let currentStatus = EKEventStore.authorizationStatus(for: .event)
    if isAuthorized(currentStatus) {
        printJSON(["granted": true, "status": statusString(currentStatus)])
        exit(0)
    }

    let sem = DispatchSemaphore(value: 0)
    var granted = false
    var resultError: String?

    store.requestFullAccessToEvents { g, error in
        granted = g
        resultError = error?.localizedDescription
        sem.signal()
    }

    let waitResult = sem.wait(timeout: .now() + timeout)
    if waitResult == .timedOut {
        printJSON(["granted": false, "status": "timeout"])
    } else {
        var obj: [String: Any] = [
            "granted": granted,
            "status": statusString(EKEventStore.authorizationStatus(for: .event)),
        ]
        if let err = resultError { obj["error"] = err }
        printJSON(obj)
    }

case "query":
    var minutes: Double = 15
    if let idx = args.firstIndex(of: "--minutes"), idx + 1 < args.count {
        minutes = Double(args[idx + 1]) ?? 15
    }

    let status = EKEventStore.authorizationStatus(for: .event)
    guard isAuthorized(status) else {
        printJSON(["authorized": false, "status": statusString(status), "events": []])
        exit(0)
    }

    let start = Date()
    let end = start.addingTimeInterval(minutes * 60)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = store.events(matching: predicate)

    var out: [[String: Any]] = []
    for event in events {
        var declined = false
        if let attendees = event.attendees {
            for attendee in attendees where attendee.isCurrentUser {
                if attendee.participantStatus == .declined {
                    declined = true
                }
                break
            }
        }

        out.append([
            "id": event.eventIdentifier ?? "",
            "title": event.title ?? "",
            "start": Int(event.startDate.timeIntervalSince1970),
            "end": Int(event.endDate.timeIntervalSince1970),
            "url": event.url?.absoluteString ?? NSNull(),
            "location": event.location ?? NSNull(),
            "notes": event.notes ?? NSNull(),
            "isAllDay": event.isAllDay,
            "declined": declined,
            "calendar": event.calendar?.title ?? "",
        ])
    }

    printJSON(["authorized": true, "events": out])

default:
    printJSON(["error": "unknown command: \(command)"])
}
