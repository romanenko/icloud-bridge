# iCloud Bridge

iCloud Bridge is a minimal local macOS bridge between MCP-compatible desktop clients and Apple Calendar and Reminders.

The menu-bar app owns EventKit access. Its MCP stdio process is a thin local proxy, so the desktop client never needs direct Calendar or Reminders permission.

## Install on macOS

From a checkout of this repository:

```sh
zsh scripts/install.sh --build
```

That one command:

- copies the signed app to `~/Applications/iCloud Bridge.app`;
- installs a stable MCP launcher at `~/.local/bin/icloud-bridge`;
- starts the bridge now and at login with a per-user LaunchAgent;
- registers a user-level MCP server in every Codex and Claude Code CLI found on `PATH`;
- builds `dist/iCloud Bridge.mcpb` for one-click Claude Desktop installation.

The client registration follows the same model as Pen: the installed executable is registered directly and globally, so it is available in every project. Existing unrelated client settings are preserved by using each client's own MCP command. Reinstalling is idempotent and migrates the legacy `icloud_bridge` Codex entry to the canonical `icloud-bridge` name.

On first launch, click iCloud Bridge in the menu bar and choose `Request Missing Access`. Grant Full Access to Calendar and Reminders as needed. Start a new Codex or Claude Code session after installation.

Codex desktop, CLI, and IDE clients on the same host share the MCP configuration. See the [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli). Claude Code's entry is installed at user scope; see the [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).

### Claude Desktop

Claude Desktop's current managed installation format is an MCP Bundle. To build the app and open Claude's normal extension review prompt in the same command, run:

```sh
zsh scripts/install.sh --build --claude-desktop
```

You can also open an already-built bundle yourself:

```sh
open "dist/iCloud Bridge.mcpb"
```

The bundle contains only the local launcher and manifest; it connects to the signed iCloud Bridge app installed above. See Anthropic's [local MCP server installation guide](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop).

### Installer choices

```sh
# Require one specific CLI integration
zsh scripts/install.sh --build --codex
zsh scripts/install.sh --build --claude

# Require both CLI integrations
zsh scripts/install.sh --build --all-integrations

# Install only the app, launcher, and LaunchAgent
zsh scripts/install.sh --build --no-integrations

# Register clients later without rebuilding the app
zsh scripts/configure-integrations.sh --all
```

The installer does not add a blanket Claude allow-rule. Calendar and reminder writes continue to use the client's normal MCP tool approval policy.

The source build must be signed with an Apple Development or Developer ID Application identity. This is required for macOS to grant the app Calendar and Reminders access. A future GitHub release can provide a signed/notarized app so users do not need to build locally.

## Build

```sh
swift build
swift test
zsh scripts/build-app.sh
zsh scripts/build-mcpb.sh
open "dist/iCloud Bridge.app"
```

Open the app once and grant Calendar and/or Reminders Full Access when macOS asks. The MCP server itself is launched by the desktop client with `--stdio`.

## MCP smoke test

After building and launching the app, run:

```sh
python3 scripts/smoke-test-mcp.py
```

The script performs MCP initialization and tool discovery, verifies both tool sets are exposed, checks Calendar and Reminders permission, lists calendars and reminder lists, and prints upcoming items.

It exits with status `3` when either permission has not been granted yet; this is an expected setup state, not an MCP transport failure.

Confirm that the clients can read back the installed registration with:

```sh
codex mcp get icloud-bridge
claude mcp get icloud-bridge
```

The repository also contains a Codex plugin package at `plugins/icloud-bridge`, with its MCP manifest at `plugins/icloud-bridge/.codex-plugin/plugin.json`. Direct CLI registration remains the default local install path because it works across Codex clients that share the host configuration.

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
