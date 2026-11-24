# Claude Tracker

A small floating window for macOS that lists every active Claude Code session (Claude Desktop and terminal), shows what each one is doing, and lets you answer the ones that need you without switching apps.

<p align="center">
  <img src="docs/screenshots/widget.png" alt="The Claude Tracker widget listing sessions by what needs you" width="300">
  <img src="docs/screenshots/popup.png" alt="The reply popup with the last message and a reply box" width="520">
</p>

Claude Code sessions pile up fast, and it is easy to miss the one waiting for you. Claude Tracker keeps them all in one small floating window, sorted so that anything needing you is on top, and lets you reply, allow or deny without switching apps.

## Screenshots

*(Made with the built-in sample data, so they show no real sessions. Regenerate them with `scripts/screenshots.sh`.)*

| | |
|---|---|
| **Needs permission:** allow or deny right in the widget, or in the popup | **Questions from Claude:** answer multiple-choice questions with one click, or type your own answer |
| <img src="docs/screenshots/popup-permission.png" alt="Permission request in the popup" width="480"> | <img src="docs/screenshots/popup-question.png" alt="A multiple-choice question in the popup" width="480"> |
| **Sub-agent counter:** the `4/6` chip shows finished out of started | |
| <img src="docs/screenshots/widget.png" alt="Widget with the sub-agent counter and a question" width="240"> | |
| **Add a session:** search your existing Desktop sessions | **Shortcuts & tips:** built in, opens on first launch |
| <img src="docs/screenshots/add-session.png" alt="The add-session search window" width="480"> | <img src="docs/screenshots/shortcuts.png" alt="The shortcuts window" width="480"> |

## Install

**You only need macOS 15 or newer.** No compiler, no Xcode.

```bash
curl -fsSL https://raw.githubusercontent.com/AliMsayleb/claude-tracker/main/install.sh | bash
```

or clone the repo and run `./install.sh`. It downloads the ready-made app from the latest release, checks its checksum, installs **Claude Tracker** into `~/Applications` and opens it. Options: `--check` (only check the requirements), `--from-source` (build it yourself; this needs the **full Xcode app**, not only the command line tools).

Prefer to download by hand? Get `Claude-Tracker.zip` from the [latest release](https://github.com/AliMsayleb/claude-tracker/releases/latest), unzip it, drag it into `~/Applications`, and run `xattr -dr com.apple.quarantine "~/Applications/Claude Tracker.app"` once (the app is not notarized yet, so macOS blocks browser downloads until you do this, or right-click > Open).

After installing:
- Open it any time with Spotlight: ⌘Space, then type "claude tracker" (or just "tracker").
- **Allow / Deny buttons:** right-click the widget header, "Set up Allow / Deny buttons…". It shows what it will change in `~/.claude/settings.json` and keeps a backup. It only applies to Claude sessions started afterwards, so restart sessions that are already open.
- Double-tap ⌘ shows or hides it. For that, grant Accessibility: right-click the widget header, "Enable double-tap ⌘ shortcut…".
- To start it at login: right-click the header, "Launch at login".

**Uninstall:** `scripts/uninstall.sh` (in the repo) removes the app, the hook and `~/.claude-widget`. Add `--purge-preferences` to also delete its saved settings. Without the repo: right-click the header > "Remove Allow / Deny hook…", then delete the app.

**Update:** run the install command again. Your settings are kept.

**Everything is local.** The widget reads Claude's local session files and talks only to your own sessions. It makes no network connections (only the installer downloads the app).

### Publishing a download (maintainers)

```bash
scripts/package.sh                       # builds dist/Claude-Tracker.zip (+ .sha256), universal: Apple Silicon and Intel
gh release create v<version> dist/Claude-Tracker.zip dist/Claude-Tracker.zip.sha256 --title "Claude Tracker <version>" --notes "..."
```

`install.sh` downloads `releases/latest/download/Claude-Tracker.zip`, so the asset names must stay the same. A zip built this way is only ad-hoc signed; the installer avoids the macOS block because `curl` downloads are not quarantined. For a smooth browser download you need an Apple Developer ID:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="my-notary-profile" scripts/package.sh
```

This signs with the hardened runtime, submits to Apple's notary service and staples the result. That path is written but has not been tested (it needs a paid developer account). Change the bundle id (`com.local.claude-widget`) before a wider release, and add a license file.

## Shortcuts and gestures

Users can see this list inside the app: right-click the widget header and choose "Shortcuts & tips…", press ⌘/ in the popup, or use the "?" button in the popup. It also opens once the first time the app starts. The list below is generated from the same source as the in-app window (`Sources/Shortcuts.swift`); run `scripts/update-readme.sh` after changing it. A test fails if they differ.

<!-- shortcuts:start -->
### Anywhere

| Shortcut | What it does |
|---|---|
| ⌘ ⌘ | Double-tap ⌘ to show or hide the widget |
| ⌘ Space | Spotlight: type “tracker” to open Claude Tracker again after quitting it |

### The widget

| Shortcut | What it does |
|---|---|
| Click | Open a session's popup to read its last message and reply |
| ⌘ Click | Open the session in your default app, Claude Desktop or Terminal (choose in the right-click menu; also marks it read) |
| ✓ on a row | Hover an unread row and click ✓ to mark it read |
| Allow Deny | Answer a permission request right in the widget |
| Option buttons | Answer a multiple-choice question from Claude right in the row (multi-select and several questions open in the popup) |
| + | Add an existing Desktop session (type to search) |
| ✕ on a row | Hover a row and click ✕ to remove it from the widget |
| ⌄ | Collapse the widget to its header, or expand it again |
| Drag header | Move the widget anywhere |
| Drag edge | Resize from the left, right or bottom edge (the size is remembered) |
| Right-click header | Choose what ⌘-click opens, set up Allow / Deny, launch at login, enable the ⌘ shortcut, shortcuts, quit |

### The reply popup

| Shortcut | What it does |
|---|---|
| Return | Send your reply |
| Shift Return | New line |
| Type Return | When Claude asks one question, your typed text is sent as your own answer |
| Esc | Close the popup |
| ⌘ W | Close the popup |
| ⌘ + | Bigger text (⌘ = works too) |
| ⌘ - | Smaller text |
| ⌘ 0 | Reset the text size |
| ⌘ Tab | Switch away and come back; your draft is kept |
| ⌘ / | Show this list |
| Open in Desktop Open in Terminal | Continue the session in either app; both mark it read |
| Drag edge | Resize the popup (the size is remembered) |

### Add a session

| Shortcut | What it does |
|---|---|
| Type | Filter by words from the title or folder |
| Return | Add the first match |
| Esc | Close |
<!-- shortcuts:end -->

## States and colors

Rows are sorted in this order, so anything that needs you is at the top.

| Order | State | Color | Meaning | Where it comes from |
|---|---|---|---|---|
| 1 | Needs permission | Red | Claude wants to run a tool and waits for Allow / Deny. The row shows the tool and command with buttons. | Registry: `waiting` + "permission" |
| 2 | Needs your answer | Orange | Claude asked a question or needs instructions. | Registry: `waiting` (any other reason) |
| 3 | New reply | Amber / yellow | Claude finished and you have not looked at the session yet. Stays until you reply or open the chat in Desktop. Opening the popup does not clear it. Desktop sessions only. | Desktop: last turn ended after you last focused the session |
| 4 | Working | Blue | Claude is running. | Registry: `busy` |
| 5 | Done | Green | Finished and you have seen it. | Registry: `idle` |
| 5 | Not running | Purple | A session you added with **+** that is not running. | Desktop session list |

Red, orange and amber rows are tinted, have a colored bar on the left, and a soft halo around their dot. Working, Done and Not running are plain. The subtitle shows the session's own one-line summary when Desktop has one (what it needs from you, or what it finished). Otherwise it shows the folder.

## Use

Build and install from a clone (needs Xcode) with `scripts/install-app.sh`. For development, `scripts/build.sh` builds `build/ClaudeWidget.app` (the same app, used by the tests) and `open build/ClaudeWidget.app` starts it.

**The widget**
- Click a row to open the reply popup. **⌘-click** a row to open the session in your default app, **Claude Desktop** or **Terminal** (choose in the right-click menu; this also marks it as read). Terminal runs `claude --resume <session>` in the session's folder.
- Hover a row to get two small buttons: **✓** (unread rows only) marks the session as read without opening it, and **✕** removes it from the widget.
- A blue **done/total** chip on a row (for example `4/6`) counts the sub-agents the session started during its current turn: finished out of started. It turns green when all are done. Agents started in the background are counted as finished when they launch.
-  Use **+** to add an existing Desktop session: a search window lists your other non-archived sessions (type to filter, Return adds the first match). Added sessions that are not running show as "Not running" (⌘-click one to resume it in Desktop).
- The chevron collapses the list to the header. Drag the left, right or bottom edge to resize (the widget has its own edge handles, and the cursor changes to a resize arrow over them; this uses a private macOS switch, "SetsCursorInBackground", because background apps cannot normally change the cursor): the width is remembered, and the height you choose becomes the maximum (the list scrolls beyond it, and the window shrinks to fit when there are fewer rows). The header buttons (collapse, **+**, ✕) highlight when you hover them; ✕ turns red.
- Right-click the header for what ⌘-click opens, "Set up Allow / Deny buttons…", "Launch at login", "Enable double-tap ⌘ shortcut…", the shortcuts window and "Quit". The ✕ in the header also quits.
- **Double-tap ⌘** shows or hides the widget. This is the only permission the widget asks for: Accessibility, so it can see the ⌘ key while another app is in front. It asks once; macOS forgets the grant whenever the app is rebuilt, so grant it again from the right-click menu.

**The reply popup**
- Shows Claude's last message (formatted: bold, italics, code, headings, lists, code blocks, tables) and a reply box. **Return** sends, **Shift-Return** adds a new line.
- It is a normal window while open: the app shows in the Dock and in ⌘Tab, and ⌘Tab brings you back to it with your draft. It stays open when you switch apps. It closes with **Esc**, **⌘W**, the ✕ button, or after you send.
- **⌘+ / ⌘- / ⌘0** make the text bigger, smaller or reset it. Drag the edges to resize. The size and text size are remembered.
- "Open in Desktop" and "Open in Terminal" in the popup header continue the session in either app.
- If the session is waiting for permission, the popup shows the request with **Allow / Deny** (when the hook is set up) and warns that a typed reply cannot approve it. Claude Code deliberately ignores approvals that arrive as messages.

## Allow / Deny and questions

They work through one `PermissionRequest` hook in `~/.claude/settings.json`. The same hook lets you answer Claude's multiple-choice questions (`AskUserQuestion`) from the widget: single-choice questions get one-click option buttons in the row, and multi-select or multi-question ones open in the popup with a Submit button. When Claude asks one question, text you type in the popup is sent as your own ("Other") answer. Plan approvals (`ExitPlanMode`) still have to be answered in Claude. Add it from the app (right-click the header > "Set up Allow / Deny buttons…") or from a clone:

```bash
scripts/install-hook.sh --dry-run   # show the change, write nothing (needs jq)
scripts/install-hook.sh             # add it (backup: settings.json.bak-claude-widget)
scripts/uninstall-hook.sh           # remove it
```

Claude Code reads hooks when a session starts, so **sessions that were already open before you set it up have no Allow / Deny**. Restart them.

The hook never blocks Claude:
- If the widget is not running, it exits at once and does nothing.
- If you answer in the normal dialog first, that works too. The hook is then cleaned up.
- It waits up to 10 minutes for a widget decision. After that the buttons disappear and only the normal dialog remains.
- Non-interactive runs (`claude -p`) wait about 5 seconds before their usual denial.
- It ignores `ExitPlanMode` (plan approval), which the widget cannot answer.

If you work mostly in auto mode, you will rarely see permission rows. The "Needs your answer" and "New reply" rows are the ones you will use most.

The question answering was verified with a real Claude session in a terminal (Claude received the answer chosen from the widget). It has not been verified with a Claude Desktop session.

## How it works

| Piece | Source |
|---|---|
| Session list and status | `~/.claude/sessions/<pid>.json`, written by every running Claude Code process (`status` is `idle`, `busy` or `waiting`). Dead processes and reused pids are filtered out. |
| Unread, summaries, existing sessions | Desktop's session records in `~/Library/Application Support/Claude/claude-code-sessions/` (`lastTurnEdgeAt`, `lastFocusedAt`, `postTurnSummary`) |
| Last message in the popup | The tail of the session transcript in `~/.claude/projects/` (re-read only when the file changes) |
| Open in Desktop | `claude://code/continue?session=<hostSessionId>` |
| Allow / Deny | `hook/permission-hook.sh` writes a request file to `~/.claude-widget/requests/`; the widget writes the decision next to it |
| Reply | The widget reads the session's `peerToken` from `~/.claude/sessions/<pid>.<hash>.key` and writes an auth line and a user message to its socket (`/tmp/cc-socks/<pid>.sock`). Claude Code delivers it as a message from another session; it does not start a new session and costs the same as typing the reply in Desktop. |

The session files and the message socket are undocumented Claude Code details and may change between versions. Cloud sessions have no local file and do not appear.

Refreshing happens off the main thread once a second, so typing stays smooth.

## Files the widget writes

- `~/.claude-widget/`: `heartbeat`, `requests/`, `state.json` (hidden, pinned and read sessions), and a copy of `permission-hook.sh`.
- Preferences (`com.local.claude-widget`): widget position and width, maximum height, collapsed state, popup size, popup text size, and whether it already asked for Accessibility.
- `~/.claude/settings.json`: only the one hook entry, and only if you run `scripts/install-hook.sh`.

## Tests

```bash
tests/run_all.sh
```

| Suite | What it covers |
|---|---|
| `hook_protocol` | The hook script: allow, deny, timeouts, widget not running, cleanup |
| `widget_logic` | Session ordering, unread, summaries, pinned/hidden, stale requests, message format (fake socket), transcript reading |
| `install_hook`, `hook_installer_app` | The settings installers (script and in-app) on temp copies |
| `ui_clicks` | Real mouse events into the panels (Allow, Deny, row click, ⌘-click, collapse, close) |
| `double_tap`, `select_all`, `return_key`, `markdown` | Double-tap ⌘ timing, ⌘A in the reply box, Return vs Shift-Return, markdown parsing |
| `popup` | Popup size memory, staying open when focus is lost, text size, ⌘W |
| `widget_window` | Search, widget height cap, the add-session window, and that test runs leave your preferences untouched |
| `widget_resize` | The edge-resize maths, scripted drags of the left, right and bottom edges, and the resize cursor areas |
| `install_app`, `uninstall`, `terminal` | The source installer and uninstaller on temp folders, and the Terminal launch script (quoting, input checks) |

Not covered by automated tests: real ⌘Tab and clipboard-manager behaviour, real mouse hover and dragging (the tests send scripted events), and replies into a Desktop session's own window. `tests/drive_claude.py` and `tests/e2e_send.py` drive a real Claude session end to end (they cost a few cents and are run by hand).

## Debug flags

`--dump` (print rows as JSON), `--sample` (fake data; never touches your real sessions or preferences), `--gc` (one cleanup pass), `--decide <id> allow|deny`, `--send <pid> <text>`, `--detail <pid>`, `--time-detail <pid>`, `--snapshot <png>` (also writes `-reply.png` / `-picker.png` for open popups), `--click <x> <y>`, `--command-click <x> <y>`, and the `--preview-hover <sf-symbol-name>` (render a header button in its hover state), and the `--test-*` flags used by the test suites. In `--sample` mode the windows are parked off-screen, so test runs never appear on your display.

## Project layout

- `Sources/`: the Swift app (`SessionRegistry` and `DesktopSessions` read state, `SessionStore` refreshes it, `WidgetView`, `ReplyView` and `AddSessionView` draw it, `WidgetApp` owns the windows).
- `hook/`: the permission hook. `scripts/`: build, icon, and hook install/uninstall scripts. `scripts/icon-concepts.swift` only renders the icon design options.
- `Info.plist`: the app is an accessory app (no Dock icon) that becomes a regular app while the popup is open.
