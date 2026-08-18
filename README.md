# iCloud Bridge

iCloud Bridge is a minimal local macOS bridge between MCP-compatible desktop clients and Apple Calendar and Reminders.

The menu-bar app owns EventKit access. Its MCP stdio process is a thin local proxy, so the desktop client never needs direct Calendar or Reminders permission.

## Install on macOS

From a checkout of this repository:

```sh
zsh scripts/install.sh --build
```

The installer copies the signed app to `~/Applications/iCloud Bridge.app`, installs the MCP launcher at `~/.local/bin/icloud-bridge`, and registers a per-user LaunchAgent so the bridge starts automatically when you log in.

On first launch, click the menu-bar item and choose `Request Missing Access`. Grant Full Access to Calendar and Reminders as needed.

The source build must be signed with an Apple Development or Developer ID Application identity. This is required for macOS to grant the app Calendar and Reminders access. A future GitHub release can provide a signed/notarized app so users do not need to build locally.

## Build

```sh
swift build
swift test
zsh scripts/build-app.sh
open "dist/iCloud Bridge.app"
```

Open the app once and grant Calendar and/or Reminders Full Access when macOS asks. The MCP server itself is launched by the desktop client with `--stdio`.

## ChatGPT desktop

In ChatGPT desktop, add a local STDIO MCP server:

- Name: `icloud-bridge`
- Command: `/bin/zsh`
- Arguments: `-lc 'exec "$HOME/.local/bin/icloud-bridge" --stdio'`

Restart the desktop app or start a new conversation after saving the server. The repository also contains a local plugin package at `plugins/icloud-bridge` with its MCP manifest at `plugins/icloud-bridge/.codex-plugin/plugin.json`.

If your desktop build exposes the local plugin directory, add this repository's `.agents/plugins/marketplace.json` as a local marketplace and install `icloud-bridge`. The direct STDIO setup above is equivalent and is the simplest fallback.

## MCP smoke test

After building and launching the app, run:

```sh
python3 scripts/smoke-test-mcp.py
```

The script performs MCP initialization and tool discovery, verifies both tool sets are exposed, checks Calendar and Reminders permission, lists calendars and reminder lists, and prints upcoming items.

It exits with status `3` when either permission has not been granted yet; this is an expected setup state, not an MCP transport failure.

## Codex configuration

```toml
[mcp_servers.icloud_bridge]
command = "/Applications/iCloud Bridge.app/Contents/MacOS/iCloudBridge"
args = ["--stdio"]
startup_timeout_sec = 10
tool_timeout_sec = 60
```

The equivalent Codex CLI command is:

```sh
codex mcp add icloud-bridge -- /bin/zsh -lc 'exec "$HOME/.local/bin/icloud-bridge" --stdio'
```

## Claude Desktop configuration

For the MVP, configure the same executable as a local stdio server using Claude Desktop's local MCP server settings. A `.mcpb` binary bundle can be added as a later packaging step.

## Tools

Calendar:

- `calendarGetStatus`
- `calendarListCalendars`
- `calendarFindEvents`
- `calendarCreateEvent`
- `calendarUpdateEvent`
- `calendarDeleteEvent`

Reminders:

- `reminderGetStatus`
- `reminderListLists`
- `reminderFindReminders`
- `reminderCreateReminder`
- `reminderUpdateReminder`
- `reminderDeleteReminder`

All data stays local to macOS and is returned only through the connected MCP client. iCloud Bridge does not store Calendar or Reminders data or Apple ID credentials.
