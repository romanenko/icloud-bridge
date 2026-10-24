#!/usr/bin/env python3
"""Test signing selection without touching the Keychain or signing an app."""
import os
from pathlib import Path
import pty
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIRST = "A" * 40
SECOND = "B" * 40
NAME = "Apple Development: Test Person (TEAMONE)"
OTHER = "Developer ID Application: Test Person (TEAMTWO)"


class SigningIdentityTests(unittest.TestCase):
    def select(self, entries, requested="", choices=None):
        env = dict(os.environ, MOCK_IDENTITIES="\n".join(
            f'  {i}) {sha} "{name}"' for i, (sha, name) in enumerate(entries, 1)
        ))
        command = ["zsh", "-c", '''
set -eu
security() { print -r -- "$MOCK_IDENTITIES"; }
source "$1/scripts/signing-identity.sh"
select_signing_identity "$2"
print -r -- "SELECTED=$SIGNING_IDENTITY"
''', "test", str(ROOT), requested]
        if choices is None:
            return subprocess.run(command, env=env, input="", capture_output=True, text=True)
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(command, env=env, stdin=slave,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            os.write(master, choices.encode())
            stdout, stderr = process.communicate(timeout=5)
            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        finally:
            os.close(master)
            os.close(slave)

    def test_single_identity(self):
        result = self.select([(FIRST, NAME)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"SELECTED={FIRST}", result.stdout)

    def test_multiple_noninteractive_requires_choice(self):
        result = self.select([(FIRST, NAME), (SECOND, OTHER)])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--signing-identity", result.stderr)

    def test_explicit_name_and_hash(self):
        for requested in (OTHER, SECOND.lower()):
            result = self.select([(FIRST, NAME), (SECOND, OTHER)], requested)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"SELECTED={SECOND}", result.stdout)

    def test_duplicate_names_require_hash(self):
        result = self.select([(FIRST, NAME), (SECOND, NAME)], NAME)
        self.assertNotEqual(result.returncode, 0)
        result = self.select([(FIRST, NAME), (SECOND, NAME)], SECOND)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_identity_or_unknown_identity(self):
        for entries, requested in (([], ""), ([(FIRST, NAME)], "missing")):
            self.assertNotEqual(self.select(entries, requested).returncode, 0)

    def test_interactive_choice_retries_invalid_input(self):
        result = self.select([(FIRST, NAME), (SECOND, OTHER)], choices="bad\n0\n3\n2\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"SELECTED={SECOND}", result.stdout)
        self.assertIn("Enter a number", result.stderr)


if __name__ == "__main__":
    unittest.main()
