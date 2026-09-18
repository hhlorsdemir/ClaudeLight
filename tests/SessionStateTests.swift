import Foundation

@main
struct SessionStateTests {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let now = Date()
        func write(_ name: String, _ value: String, age: TimeInterval) throws {
            let url = directory.appendingPathComponent(name)
            try value.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        func state() -> LightState { readState(directory: directory.path, now: now) }

        assert(state().idle && state().latestAgent == nil)
        try write("claude-session", "working", age: 30)
        assert(state().latestAgent == .claude)
        try write("codex-session", "working", age: 20)
        assert(state().latestAgent == .codex)
        try write("claude-session", "waiting", age: 10)
        assert(state().latestAgent == .claude && state().waiting && state().working)
        try write("codex-session", "working", age: 5)
        assert(state().latestAgent == .codex && state().waiting)
        // New invalid/hidden files must not take over click routing.
        try write("invalid", "garbage", age: 1)
        try write(".temporary", "waiting", age: 0)
        assert(state().latestAgent == .codex)
        try fm.removeItem(at: directory.appendingPathComponent("codex-session"))
        assert(state().latestAgent == .claude)
        try write("claude-session", "working", age: staleAfter + 1)
        assert(state().latestAgent == nil && state().idle)
        assert(readState(directory: directory.appendingPathComponent("missing").path).latestAgent == nil)
        assert(CodingAgent.codex.bundleIdentifier == "com.openai.codex")
        assert(CodingAgent.claude.bundleIdentifier == "com.anthropic.claudefordesktop")
        print("Session selection tests passed")
    }
}
