"""Isolated installer regressions; a fake `claude` records calls and never contacts a service."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_CLAUDE = r'''#!/usr/bin/env bash
echo "$*" >> "$TEST_CALLS"
case "$*" in
  "plugin marketplace list") [ "${HAVE_MARKETPLACE:-0}" = 1 ] && printf '  \xe2\x9d\xaf hirey\n'; exit 0 ;;
  "plugin list") [ "${HAVE_PLUGIN:-0}" = 1 ] && printf '  \xe2\x9d\xaf hirey-hi@hirey\n'; exit 0 ;;
  "plugin install hirey-hi@hirey") [ "${FAIL_INSTALL:-0}" = 1 ] && exit 1; exit 0 ;;
esac
exit 0
'''
LEGACY_SKILL = "---\nname: hi-use\n---\nCall https://hi.hirey.ai/v1/... with curl.\n"


class InstallTests(unittest.TestCase):
    def run_install(self, env_extra=None, claude=True, skills=None):
        tmp = tempfile.TemporaryDirectory(prefix="hi-claude-install-")
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for tool in ("bash", "grep", "mkdir", "mv", "date", "env"):
            path = subprocess.run(["/usr/bin/which", tool], capture_output=True, text=True).stdout.strip()
            (bin_dir / tool).symlink_to(path)
        if claude:
            fake = bin_dir / "claude"
            fake.write_text(FAKE_CLAUDE)
            fake.chmod(0o755)
        skills_dir = root / "skills"
        skills_dir.mkdir()
        for name, text in (skills or {}).items():
            (skills_dir / name).mkdir()
            (skills_dir / name / "SKILL.md").write_text(text)
        calls = root / "calls"
        calls.touch()
        env = {"PATH": str(bin_dir), "HOME": str(root), "SKILLS_DIR": str(skills_dir), "TEST_CALLS": str(calls)}
        env.update(env_extra or {})
        result = subprocess.run([str(bin_dir / "bash"), str(ROOT / "install.sh")], env=env, capture_output=True, text=True)
        return result, calls.read_text().splitlines(), skills_dir

    def test_fresh_install_adds_marketplace_and_installs(self):
        result, calls, _ = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plugin marketplace add hirey-ai/hirey-claude-plugin", calls)
        self.assertIn("plugin install hirey-hi@hirey", calls)
        self.assertIn("claude mcp login plugin:hirey-hi:hi", result.stdout)

    def test_rerun_updates_instead_of_adding(self):
        result, calls, _ = self.run_install({"HAVE_MARKETPLACE": "1", "HAVE_PLUGIN": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plugin marketplace update hirey", calls)
        self.assertIn("plugin update hirey-hi@hirey", calls)
        self.assertNotIn("plugin install hirey-hi@hirey", calls)

    def test_legacy_rest_skills_are_moved_not_deleted(self):
        other = "---\nname: hi-events\n---\nSomeone else's skill.\n"
        result, _, skills_dir = self.run_install(skills={"hi-use": LEGACY_SKILL, "hi-onboard": LEGACY_SKILL, "hi-events": other})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((skills_dir / "hi-use").exists())
        self.assertFalse((skills_dir / "hi-onboard").exists())
        self.assertEqual((skills_dir / "hi-events" / "SKILL.md").read_text(), other)
        legacy = [p for p in skills_dir.iterdir() if p.name.startswith(".hirey-legacy-")]
        self.assertEqual(len(legacy), 1)
        self.assertEqual((legacy[0] / "hi-use" / "SKILL.md").read_text(), LEGACY_SKILL)

    def test_install_failure_is_reported(self):
        result, _, _ = self.run_install({"FAIL_INSTALL": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not install hirey-hi@hirey", result.stderr)

    def test_no_claude_binary_points_elsewhere(self):
        result, calls, _ = self.run_install(claude=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Claude Code ('claude') not found", result.stderr)
        self.assertEqual(calls, [])

    def test_plugin_declares_hosted_mcp(self):
        import json
        mcp = json.loads((ROOT / "plugins/hirey-hi/.mcp.json").read_text())["mcpServers"]["hi"]
        manifest = json.loads((ROOT / "plugins/hirey-hi/.claude-plugin/plugin.json").read_text())
        self.assertEqual(mcp["url"], "https://mcp.hirey.ai/mcp")
        self.assertEqual(mcp["headers"]["x-hirey-plugin-version"], manifest["version"])
        self.assertIn(f'VERSION="{manifest["version"]}"', (ROOT / "install.sh").read_text())


if __name__ == "__main__":
    unittest.main()
