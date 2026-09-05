"""Isolated installer/onboarding regressions; fake curl never contacts a service."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
assert "--connect-timeout" in args and "--max-time" in args, "unbounded HTTP call"
assert any(a.startswith("-") and "f" in a and not a.startswith("--") for a in args), "HTTP errors not rejected"
url = next(a for a in args if a.startswith("https://"))
mode = os.environ["TEST_MODE"]
with open(os.environ["TEST_CALLS"], "a") as f: f.write(url + "\n")
if "raw.githubusercontent.com" in url:
    if mode == "download_failure" and "hi-events/" in url: sys.exit(28)
    pathlib.Path(args[args.index("-o") + 1]).write_text("new skill\n")
elif url.endswith("/register"):
    if mode == "http_failure": sys.exit(22)
    if mode == "timeout": sys.exit(28)
    if mode == "bad_registration":
        print('{"error":"oops","debug":"TEST_SECRET_SENTINEL"}')
    else:
        print(json.dumps({"auth":{"client_id":"client","client_secret":"TEST_SECRET_SENTINEL","audience":"hi"}, "agent":{"agent_id":"agent"}, "installation":{"installation_id":"install"}}))
elif url.endswith("/oauth/token"):
    if mode == "bad_token": print('{"error":"invalid_grant","debug":"TEST_SECRET_SENTINEL"}')
    else: print('{"access_token":"TEST_TOKEN_SENTINEL","expires_in":3600}')
elif url.endswith("/agents/me"):
    print('{"agent":{"agent_id":"agent","status":"pending"},"installation":{"installation_id":"install"}}')
else: sys.exit(99)
'''

class BootstrapTests(unittest.TestCase):
    def run_case(self, source, mode, existing=None):
        with tempfile.TemporaryDirectory(prefix="hi-claude-test-") as tmp:
            task_dir = Path(tmp)
            bin_dir = task_dir / "bin"
            bin_dir.mkdir()
            fake = bin_dir / "curl"
            fake.write_text(FAKE_CURL)
            fake.chmod(0o755)
            creds_dir = task_dir / "xdg" / "hi"
            creds_dir.mkdir(parents=True)
            creds = creds_dir / "credentials.json"
            if existing is not None:
                creds.write_text(existing)
                creds.chmod(0o600)
            skills = task_dir / "skills"
            for name in ("hi-onboard", "hi-use", "hi-events", "hi-repair"):
                path = skills / name
                path.mkdir(parents=True)
                (path / "SKILL.md").write_text("old skill\n")
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                       XDG_CONFIG_HOME=str(task_dir / "xdg"), CREDS_DIR=str(creds_dir),
                       SKILLS_DIR=str(skills), HI_FORCE_INSTALL="1",
                       HI_BASE="https://fixture.invalid", TEST_MODE=mode,
                       TEST_CALLS=str(task_dir / "calls"))
            if source == "installer":
                command = ["bash", str(ROOT / "install.sh")]
                data = None
            else:
                text = (ROOT / "plugins/hirey-hi/skills/hi-onboard/SKILL.md").read_text()
                data = next(block for block in re.findall(r"```bash\n(.*?)```", text, re.S) if "set -euo pipefail" in block)
                command = ["bash"]
            result = subprocess.run(command, input=data, text=True, env=env, capture_output=True, timeout=15)
            self.assertNotIn("TEST_SECRET_SENTINEL", result.stdout + result.stderr)
            self.assertNotIn("TEST_TOKEN_SENTINEL", result.stdout + result.stderr)
            calls = (task_dir / "calls").read_text() if (task_dir / "calls").exists() else ""
            stored = creds.read_text() if creds.exists() else None
            permissions = (creds.stat().st_mode & 0o777) if creds.exists() else None
            old_skills = all((skills / n / "SKILL.md").read_text() == "old skill\n" for n in ("hi-onboard", "hi-use", "hi-events", "hi-repair"))
            self.assertFalse(list(creds_dir.glob(".credentials.*")))
            self.assertFalse((creds_dir / ".register.lock").exists())
            return result.returncode, stored, permissions, calls, old_skills

    def test_failed_registration_never_persists_credentials(self):
        for source in ("installer", "skill"):
            for mode in ("http_failure", "bad_registration", "timeout"):
                with self.subTest(source=source, mode=mode):
                    code, stored, _, calls, _ = self.run_case(source, mode)
                    self.assertNotEqual(code, 0)
                    self.assertIsNone(stored)
                    self.assertNotIn("/oauth/token", calls)

    def test_refresh_failure_preserves_existing_identity(self):
        existing = json.dumps({"client_id":"same-client","client_secret":"TEST_SECRET_SENTINEL","agent_id":"same-agent","audience":"hi"})
        for source in ("installer", "skill"):
            with self.subTest(source=source):
                code, stored, _, calls, _ = self.run_case(source, "bad_token", existing)
                self.assertNotEqual(code, 0)
                self.assertEqual(stored, existing)
                self.assertNotIn("/register", calls)

    def test_corrupt_existing_identity_is_not_replaced(self):
        for source in ("installer", "skill"):
            with self.subTest(source=source):
                code, stored, _, calls, _ = self.run_case(source, "ok", "{}")
                self.assertNotEqual(code, 0)
                self.assertEqual(stored, "{}")
                self.assertNotIn("/register", calls)

    def test_success_has_private_credentials(self):
        for source in ("installer", "skill"):
            with self.subTest(source=source):
                code, stored, mode, _, _ = self.run_case(source, "ok")
                self.assertEqual(code, 0)
                self.assertEqual(mode, 0o600)
                self.assertEqual(json.loads(stored)["client_id"], "client")

    def test_failed_download_does_not_partially_upgrade(self):
        code, stored, _, calls, old = self.run_case("installer", "download_failure")
        self.assertNotEqual(code, 0)
        self.assertIsNone(stored)
        self.assertTrue(old)
        self.assertNotIn("/register", calls)

if __name__ == "__main__":
    unittest.main()
