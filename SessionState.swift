import Foundation

enum CodingAgent: Equatable {
    case claude, codex

    var bundleIdentifier: String {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex: return "com.openai.codex"
        }
    }
}

struct LightState: Equatable {
    var working = false
    var waiting = false
    var latestAgent: CodingAgent?
    var idle: Bool { !working && !waiting }
}

let stateDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/claude-light/state")
let staleAfter: TimeInterval = 12 * 3600

func readState(directory: String = stateDir, now: Date = Date()) -> LightState {
    let fm = FileManager.default
    var state = LightState()
    var latestUpdate = Date.distantPast
    guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return state }
    // Sorting makes equal-timestamp selection deterministic.
    for file in files.sorted() where !file.hasPrefix(".") {
        let path = (directory as NSString).appendingPathComponent(file)
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              now.timeIntervalSince(modified) <= staleAfter,
              let value = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "working": state.working = true
        case "waiting": state.waiting = true
        default: continue
        }
        if modified > latestUpdate {
            latestUpdate = modified
            state.latestAgent = file.hasPrefix("codex-") ? .codex : .claude
        }
    }
    return state
}
