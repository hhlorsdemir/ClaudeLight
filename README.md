# ClaudeLight

A tiny traffic light that sits on the edge of your Mac screen and shows what [Claude Code](https://claude.com/claude-code) and Codex are doing, so you can work on something else and glance instead of switching windows.

<img src="docs/mockup.png" width="800" alt="ClaudeLight on the right edge of a MacBook screen">

- **Green** – at least one tracked session is working
- **Yellow** – a tracked session needs input or approval; takes priority over green
- **Red** – no tracked session is working or waiting

Claude Code keeps its existing behavior: an open session waiting for the next prompt is yellow. Codex is green during a turn, yellow while requesting approval or input through a supported tool hook, and inactive after completion or interruption. An idle Codex conversation does not keep the light on.

The installer registers Codex lifecycle hooks when it finds Codex or its configuration directory. Both providers contribute to the same indicator.

## Install

Requires macOS 13+, Xcode Command Line Tools (`xcode-select --install`) and `jq` (`brew install jq`). If you received a zip that already contains `ClaudeLight.app`, the Command Line Tools are optional; the installer uses the prebuilt app when `swiftc` is missing.

```bash
git clone https://github.com/hhlorsdemir/ClaudeLight.git
cd ClaudeLight
./install.sh
```

This builds the app, copies it to `~/Applications`, installs a small hook script, registers the hooks in `~/.claude/settings.json` (a backup is kept next to it), adds ClaudeLight as a login item and launches it. Codex hooks are registered in `${CODEX_HOME:-~/.codex}/hooks.json` when Codex is detected. Use `./install.sh --no-login` to skip the login item.

For Codex, use a version that supports lifecycle hooks. After installation, open `/hooks` in Codex CLI and review and trust the ClaudeLight hooks. Codex skips untrusted hooks. Then start a new session so it loads the updated configuration. Existing sessions are not retroactively tracked. See the [official Codex hooks documentation](https://developers.openai.com/es-419/docs/hooks).

Tracking depends on the client emitting these hooks; merely leaving the Codex app open does not count as activity. Some specialized tools bypass tool hooks, so their input requests may not be observable.

## Use

- **Left click** – bring the Claude desktop app to the front (launches it if closed)
- **Drag** – move the light up or down; it stays glued to the edge
- **Right click** – snap to the left or right edge, switch to compact single-light mode, quit

Compact mode shows one dot with priority yellow → green → red. All choices are remembered.
The light is hidden from the Dock, shows on every Space and stays above full-screen apps.

## How it works

Claude Code and Codex hooks call `~/.claude/hooks/claude-light.sh`. The script writes one small file per session under `~/.claude/claude-light/state/` containing `working` or `waiting`. Codex files use a `codex-` prefix to keep the providers independent. The app polls that folder every 0.7 seconds. Updates are atomic, and malformed payloads are ignored.

| Codex event | State |
|---|---|
| `UserPromptSubmit`, ordinary `PreToolUse`, `PostToolUse` | working |
| `PreCompact`, `PostCompact`, `SessionStart` with source `compact` | working |
| `PermissionRequest`, `PreToolUse` for `request_user_input` | waiting |
| `Stop`, `Interrupt`, `SessionEnd`, other `SessionStart` | file removed |

Claude hooks retain their mappings: tool use and prompts mean working; session start, stop, notifications and permission requests mean waiting; session end removes the file.

Files older than 12 hours are ignored, so a session that was killed without a clean exit does not keep a light on forever.

## Customize

Sizes and colours are constants at the top of `main.swift` (`normalSize`, `compactSize`, dot size `d`, spacing `gap`, edge curve `flare`). After editing:

```bash
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Removes the app, the hook script, the hook entries from Claude `settings.json` and Codex `hooks.json` (other hooks are left untouched), the login item and the state files.

## Verification

Run the hook regression tests with `python3 -m unittest discover -s tests -v`, then build with `./build.sh`.

For a live Codex check after trusting the hooks: submit a prompt (green), trigger an approval or supported input request (yellow), respond (green), and let the turn finish (red if no other sessions are active). Repeat with two sessions to check that a waiting session takes priority.

## License

MIT
