"""Regression tests for the scheduled-backup fail-closed orchestration contract."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_SCRIPT = Path(__file__).with_name("scheduled-backup.sh")
SERVICE_UNIT = REPOSITORY_ROOT / "deploy" / "systemd" / "flowlesshub-backup.service"


class ScheduledBackupOrchestratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="flowlesshub-scheduled-backup-")
        self.root = Path(self.temp_dir.name)
        self.scripts_dir = self.root / "scripts" / "vps"
        self.runtime_dir = self.root / ".vps-runtime"
        self.backup_dir = self.runtime_dir / "backups"
        self.scripts_dir.mkdir(parents=True)
        self.backup_dir.mkdir(parents=True)
        self.runtime_dir.chmod(0o700)

        self.script = self.scripts_dir / "scheduled-backup.sh"
        self.script.write_bytes(SOURCE_SCRIPT.read_bytes())
        self.script.chmod(0o755)

        self.backup_script = self.scripts_dir / "backup-db.sh"
        self.backup_script.write_text(
            "#!/usr/bin/env bash\n"
            "set -Eeuo pipefail\n"
            'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"\n'
            'ARCHIVE="$ROOT/.vps-runtime/backups/flowlesshub-20261113T200000Z.dump"\n'
            'printf "fixture archive\\n" > "$ARCHIVE"\n'
            'printf "Archive: %s\\n" "$ARCHIVE"\n',
            encoding="utf-8",
            newline="\n",
        )
        self.offsite_script = self.scripts_dir / "offsite-backup.sh"
        self.offsite_script.write_text(
            "#!/usr/bin/env bash\n"
            "set -Eeuo pipefail\n"
            'printf "%s\\n" "$*" >> "$TEST_OFFSITE_LOG"\n'
            'exit "${TEST_OFFSITE_STATUS:-0}"\n',
            encoding="utf-8",
            newline="\n",
        )
        self.retention_script = self.scripts_dir / "backup-retention.sh"
        self.retention_script.write_text(
            "#!/usr/bin/env bash\n"
            "set -Eeuo pipefail\n"
            'printf "%s\\n" "$*" >> "$TEST_RETENTION_LOG"\n',
            encoding="utf-8",
            newline="\n",
        )
        # Use Git Bash chmod so POSIX executable bits are established on Windows too.
        subprocess.run(
            [
                "bash",
                "-c",
                "chmod 0755 scripts/vps/backup-db.sh scripts/vps/offsite-backup.sh scripts/vps/backup-retention.sh",
            ],
            cwd=self.root,
            check=True,
            text=True,
            capture_output=True,
        )

        self.offsite_log = self.root / "offsite.log"
        self.retention_log = self.root / "retention.log"
        self.base_env = os.environ.copy()
        self.base_env.update(
            {
                "TEST_OFFSITE_LOG": self.offsite_log.name,
                "TEST_RETENTION_LOG": self.retention_log.name,
            }
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_orchestrator(
        self, *, required: bool = True, offsite_status: int = 0
    ) -> subprocess.CompletedProcess[str]:
        # Set fixture variables inside Git Bash itself. This avoids relying on
        # Windows CreateProcess/MSYS environment propagation for custom keys.
        required_value = "1" if required else ""
        bash_setup = (
            f"export FLOWLESSHUB_OFFSITE_REQUIRED={required_value}\n"
            f"export TEST_OFFSITE_STATUS={offsite_status}\n"
            f"export TEST_OFFSITE_LOG={self.offsite_log.name}\n"
            f"export TEST_RETENTION_LOG={self.retention_log.name}\n"
            "exec bash scripts/vps/scheduled-backup.sh\n"
        )
        return subprocess.run(
            ["bash", "-c", bash_setup],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_systemd_service_sets_mandatory_offsite_flag(self) -> None:
        service = SERVICE_UNIT.read_text(encoding="utf-8")
        self.assertIn("Environment=FLOWLESSHUB_OFFSITE_REQUIRED=1\n", service)

    def test_refuses_to_start_without_required_offsite_flag(self) -> None:
        result = self.run_orchestrator(required=False, offsite_status=0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OFFSITE_REQUIRED", result.stderr)
        self.assertFalse(any(self.backup_dir.iterdir()))
        self.assertFalse(self.offsite_log.exists())
        self.assertFalse(self.retention_log.exists())

    def test_disabled_or_unconfigured_offsite_fails_and_skips_retention(self) -> None:
        result = self.run_orchestrator(offsite_status=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OFFSITE_REQUIRED", result.stderr)
        self.assertTrue(self.offsite_log.exists())
        self.assertFalse(self.retention_log.exists())
        self.assertNotIn("Scheduled backup workflow completed", result.stdout)

    def test_offsite_upload_failure_fails_and_skips_retention(self) -> None:
        result = self.run_orchestrator(offsite_status=23)
        self.assertEqual(result.returncode, 23)
        self.assertIn("Off-site upload failed", result.stderr)
        self.assertFalse(self.retention_log.exists())
        self.assertNotIn("Scheduled backup workflow completed", result.stdout)

    def test_verified_offsite_success_allows_retention_dry_run_and_service_success(self) -> None:
        result = self.run_orchestrator(offsite_status=0)
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("Off-site stage: uploaded and snapshot read-back confirmed.", result.stdout)
        self.assertIn("Scheduled backup workflow completed.", result.stdout)
        self.assertEqual(self.retention_log.read_text(encoding="utf-8").strip(), "--dry-run")


if __name__ == "__main__":
    unittest.main()
