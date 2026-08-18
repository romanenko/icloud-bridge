#!/usr/bin/env python3
"""Exercise iCloud Bridge through the same local stdio MCP path as a client."""

from __future__ import annotations

import argparse
import json
import os
import selectors
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


class MCPClient:
    def __init__(self, executable: Path, timeout: float) -> None:
        self.timeout = timeout
        self.process = subprocess.Popen(
            [str(executable), "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.next_id = 1

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if self.process.stdin is None or self.process.stdout is None:
            raise RuntimeError("MCP process pipes are unavailable")

        request_id = self.next_id
        self.next_id += 1
        message: dict[str, Any] = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
        }
        if params is not None:
            message["params"] = params

        self.process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            ready = selector.select(self.timeout)
        finally:
            selector.close()

        if not ready:
            raise TimeoutError(f"Timed out waiting for MCP response to {method}")

        line = self.process.stdout.readline()
        if not line:
            stderr = self.process.stderr.read() if self.process.stderr else ""
            raise RuntimeError(f"MCP process exited before replying to {method}: {stderr.strip()}")

        response = json.loads(line)
        if "error" in response:
            raise RuntimeError(f"{method} failed: {response['error']}")
        return response["result"]

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        if self.process.stdin is None:
            raise RuntimeError("MCP process stdin is unavailable")
        message: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        self.process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def call_tool(self, name: str, arguments: dict[str, Any]) -> Any:
        result = self.request(
            "tools/call",
            {"name": name, "arguments": arguments},
        )
        if result.get("isError"):
            message = result.get("content", [{"text": "unknown MCP tool error"}])[0]["text"]
            raise RuntimeError(message)

        if "structuredContent" in result:
            return result["structuredContent"]

        content = result.get("content", [])
        if content and content[0].get("type") == "text":
            return json.loads(content[0]["text"])
        return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    default_executable = root / "dist" / "iCloud Bridge.app" / "Contents" / "MacOS" / "iCloudBridge"
    parser.add_argument(
        "--executable",
        type=Path,
        default=Path(os.environ.get("CALENDAR_BRIDGE_EXECUTABLE", default_executable)),
        help="iCloud Bridge executable to launch (defaults to the built app bundle).",
    )
    parser.add_argument("--days", type=int, default=7, help="Number of future days to search.")
    parser.add_argument("--limit", type=int, default=25, help="Maximum upcoming events to print.")
    parser.add_argument("--timeout", type=float, default=10, help="Seconds to wait for each MCP response.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.executable.is_file():
        print(f"Executable not found: {args.executable}", file=sys.stderr)
        return 2

    client = MCPClient(args.executable, args.timeout)
    try:
        initialize = client.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "icloud-bridge-smoke-test", "version": "0.1.0"},
            },
        )
        client.notify("notifications/initialized")
        tools = client.request("tools/list").get("tools", [])
        tool_names = [tool["name"] for tool in tools]

        print("MCP connection: OK")
        print(f"Server: {initialize['serverInfo']['name']} {initialize['serverInfo']['version']}")
        print(f"Protocol: {initialize['protocolVersion']}")
        print(f"Tools: {', '.join(tool_names)}")

        expected_tools = {
            "calendarGetStatus",
            "calendarListCalendars",
            "calendarFindEvents",
            "calendarCreateEvent",
            "calendarUpdateEvent",
            "calendarDeleteEvent",
            "reminderGetStatus",
            "reminderListLists",
            "reminderFindReminders",
            "reminderCreateReminder",
            "reminderUpdateReminder",
            "reminderDeleteReminder",
        }
        missing_tools = expected_tools.difference(tool_names)
        if missing_tools:
            raise RuntimeError(f"tools/list is missing: {', '.join(sorted(missing_tools))}")

        start = datetime.now(timezone.utc).replace(microsecond=0)
        end = start + timedelta(days=args.days)
        access_ready = True

        calendar_status = client.call_tool("calendarGetStatus", {})
        print(f"Calendar access: {calendar_status['authorization']} — {calendar_status['message']}")
        if calendar_status["authorization"] == "full_access":
            calendars = client.call_tool("calendarListCalendars", {}).get("items", [])
            print(f"Calendars ({len(calendars)}):")
            for calendar in calendars:
                default_marker = " [default]" if calendar.get("isDefault") else ""
                writable_marker = "writable" if calendar.get("writable") else "read-only"
                print(f"  - {calendar['title']} ({calendar.get('source') or 'unknown source'}, {writable_marker}){default_marker}")

            events = client.call_tool(
                "calendarFindEvents",
                {
                    "start": start.isoformat().replace("+00:00", "Z"),
                    "end": end.isoformat().replace("+00:00", "Z"),
                    "calendarIDs": [],
                    "limit": args.limit,
                },
            ).get("items", [])
            print(f"Upcoming events ({len(events)} in the next {args.days} days):")
            for event in events:
                print(f"  - {event['start']} | {event['title']} | {event['calendarTitle']}")
        else:
            access_ready = False
            print("Calendar data: unavailable until iCloud Bridge has Full Access.")

        reminder_status = client.call_tool("reminderGetStatus", {})
        print(f"Reminders access: {reminder_status['authorization']} — {reminder_status['message']}")
        if reminder_status["authorization"] == "full_access":
            lists = client.call_tool("reminderListLists", {}).get("items", [])
            print(f"Reminder lists ({len(lists)}):")
            for reminder_list in lists:
                default_marker = " [default]" if reminder_list.get("isDefault") else ""
                writable_marker = "writable" if reminder_list.get("writable") else "read-only"
                print(f"  - {reminder_list['title']} ({reminder_list.get('source') or 'unknown source'}, {writable_marker}){default_marker}")

            reminders = client.call_tool(
                "reminderFindReminders",
                {
                    "start": start.isoformat().replace("+00:00", "Z"),
                    "end": end.isoformat().replace("+00:00", "Z"),
                    "listIDs": [],
                    "includeCompleted": False,
                    "limit": args.limit,
                },
            ).get("items", [])
            print(f"Upcoming reminders ({len(reminders)} in the next {args.days} days):")
            for reminder in reminders:
                due = reminder.get("due") or "no due date"
                print(f"  - {due} | {reminder['title']} | {reminder['listTitle']}")
        else:
            access_ready = False
            print("Reminder data: unavailable until iCloud Bridge has Full Access.")

        return 0 if access_ready else 3
    except (RuntimeError, TimeoutError, json.JSONDecodeError) as error:
        print(f"MCP smoke test failed: {error}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
