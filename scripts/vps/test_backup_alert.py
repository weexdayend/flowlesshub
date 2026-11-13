"""Offline unit tests for the FlowlessHub Discord backup notifier."""

from __future__ import annotations

import io
import json
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import Mock
from urllib.error import HTTPError

SCRIPT_PATH = Path(__file__).resolve().with_name("backup-alert.py")
SPEC = importlib.util.spec_from_file_location("backup_alert", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Unable to load backup-alert.py")
backup_alert = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup_alert)


VALID_URL = "https://discord.com/api/webhooks/123456789012345678/Abc_def-123456789"


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200) -> None:
        self.body = body
        self.status = status
        self.closed = False

    def getcode(self) -> int:
        return self.status

    def read(self, _limit: int = -1) -> bytes:
        return self.body

    def close(self) -> None:
        self.closed = True


class BackupAlertTests(unittest.TestCase):
    def test_webhook_url_adds_wait_true(self) -> None:
        result = backup_alert.validate_webhook_url(VALID_URL)
        self.assertEqual(result, VALID_URL + "?wait=true")

    def test_post_accepts_prevalidated_webhook_url(self) -> None:
        opener = Mock()
        response = FakeResponse(json.dumps({"id": "123456789012345678"}).encode())
        opener.open.return_value = response
        normalized_url = backup_alert.validate_webhook_url(VALID_URL)

        message_id = backup_alert.post_message(normalized_url, "test", opener=opener)

        self.assertEqual(message_id, "123456789012345678")
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, normalized_url)

    def test_webhook_rejects_non_discord_host_and_redirect_parameters(self) -> None:
        bad_urls = (
            "http://discord.com/api/webhooks/1/token",
            "https://evil.example/api/webhooks/1/token",
            "https://discord.com.evil.example/api/webhooks/1/token",
            "https://user:pass@discord.com/api/webhooks/1/token",
            VALID_URL + "?thread_id=123",
            VALID_URL + "#fragment",
            "https://discord.com/api/webhooks/1/token/extra",
        )
        for value in bad_urls:
            with self.subTest(value=value):
                with self.assertRaises(backup_alert.AlertDeliveryError):
                    backup_alert.validate_webhook_url(value)

    def test_message_disables_mentions(self) -> None:
        message = backup_alert.build_message("test", {})
        self.assertIn("Manual Discord delivery test", message)
        self.assertNotIn("@everyone", message)

    def test_success_context_must_match_backup_unit(self) -> None:
        env = {
            "MONITOR_UNIT": "other.service",
            "MONITOR_SERVICE_RESULT": "success",
            "MONITOR_EXIT_CODE": "exited",
            "MONITOR_EXIT_STATUS": "0",
        }
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "context_mismatch"):
            backup_alert.build_message("success", env)

    def test_success_message_does_not_claim_offsite_success(self) -> None:
        env = {
            "MONITOR_UNIT": "flowlesshub-backup.service",
            "MONITOR_SERVICE_RESULT": "success",
            "MONITOR_EXIT_CODE": "exited",
            "MONITOR_EXIT_STATUS": "0",
        }
        message = backup_alert.build_message("success", env)
        self.assertIn("Off-site state is stage-specific", message)
        self.assertNotIn("R2 upload succeeded", message)

    def test_failure_context_requires_actual_failure(self) -> None:
        env = {
            "MONITOR_UNIT": "flowlesshub-backup.service",
            "MONITOR_SERVICE_RESULT": "success",
            "MONITOR_EXIT_CODE": "exited",
            "MONITOR_EXIT_STATUS": "0",
        }
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "context_mismatch"):
            backup_alert.build_message("failure", env)

    def test_post_accepts_only_discord_message_id(self) -> None:
        opener = Mock()
        response = FakeResponse(json.dumps({"id": "123456789012345678"}).encode())
        opener.open.return_value = response
        message_id = backup_alert.post_message(VALID_URL, "test", opener=opener)
        self.assertEqual(message_id, "123456789012345678")
        self.assertTrue(response.closed)
        request = opener.open.call_args.args[0]
        self.assertTrue(request.full_url.endswith("?wait=true"))
        self.assertEqual(json.loads(request.data)["allowed_mentions"], {"parse": []})

    def test_post_retries_explicit_429_with_bounded_retry_after(self) -> None:
        opener = Mock()
        rate_limit = HTTPError(
            VALID_URL,
            429,
            "rate limited",
            {"Retry-After": "0.25"},
            io.BytesIO(b'{"retry_after":0.25}'),
        )
        opener.open.side_effect = [rate_limit, FakeResponse(b'{"id":"123456789012345678"}')]
        sleep = Mock()
        message_id = backup_alert.post_message(VALID_URL, "test", opener=opener, sleep_fn=sleep)
        self.assertEqual(message_id, "123456789012345678")
        sleep.assert_called_once_with(0.25)
        self.assertEqual(opener.open.call_count, 2)

    def test_post_does_not_retry_ambiguous_server_error(self) -> None:
        opener = Mock()
        opener.open.side_effect = HTTPError(
            VALID_URL, 500, "server error", {}, io.BytesIO(b"ignored")
        )
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "http_500"):
            backup_alert.post_message(VALID_URL, "test", opener=opener)
        self.assertEqual(opener.open.call_count, 1)

    def test_post_rejects_rate_limit_wait_over_budget(self) -> None:
        opener = Mock()
        opener.open.side_effect = HTTPError(
            VALID_URL, 429, "rate limited", {"Retry-After": "10"}, io.BytesIO(b"{}")
        )
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "outside_budget"):
            backup_alert.post_message(VALID_URL, "test", opener=opener)
        self.assertEqual(opener.open.call_count, 1)

    def test_post_rejects_response_without_message_id(self) -> None:
        opener = Mock()
        opener.open.return_value = FakeResponse(b'{"type":0}')
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "message_id_missing"):
            backup_alert.post_message(VALID_URL, "test", opener=opener)

    def test_post_does_not_retry_transport_timeout(self) -> None:
        opener = Mock()
        opener.open.side_effect = TimeoutError("synthetic timeout")
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "outcome_unknown_no_retry"):
            backup_alert.post_message(VALID_URL, "test", opener=opener)
        self.assertEqual(opener.open.call_count, 1)

    def test_synthetic_systemd_events_are_explicitly_labeled(self) -> None:
        fixtures = {
            "test-success": {
                "MONITOR_UNIT": "flowlesshub-alert-test-success.service",
                "MONITOR_SERVICE_RESULT": "success",
                "MONITOR_EXIT_CODE": "exited",
                "MONITOR_EXIT_STATUS": "0",
            },
            "test-failure": {
                "MONITOR_UNIT": "flowlesshub-alert-test-failure.service",
                "MONITOR_SERVICE_RESULT": "exit-code",
                "MONITOR_EXIT_CODE": "exited",
                "MONITOR_EXIT_STATUS": "1",
            },
        }
        for event, context in fixtures.items():
            with self.subTest(event=event):
                message = backup_alert.build_message(event, context)
                self.assertIn("[TEST — SYNTHETIC", message)
                self.assertIn("disposable systemd lifecycle test", message)

    def test_synthetic_event_rejects_unexpected_source_unit(self) -> None:
        env = {
            "MONITOR_UNIT": "flowlesshub-backup.service",
            "MONITOR_SERVICE_RESULT": "success",
            "MONITOR_EXIT_CODE": "exited",
            "MONITOR_EXIT_STATUS": "0",
        }
        with self.assertRaisesRegex(backup_alert.AlertDeliveryError, "synthetic_event_context_mismatch"):
            backup_alert.build_message("test-success", env)

    def test_alert_systemd_unit_keeps_independent_hardened_lifecycle(self) -> None:
        root = Path(__file__).resolve().parents[2]
        backup_unit = (root / "deploy/systemd/flowlesshub-backup.service").read_text()
        alert_unit = (root / "deploy/systemd/flowlesshub-backup-alert@.service").read_text()
        self.assertIn("OnSuccess=flowlesshub-backup-alert@success.service", backup_unit)
        self.assertIn("OnFailure=flowlesshub-backup-alert@failure.service", backup_unit)
        self.assertIn("LoadCredential=discord-webhook-url:/opt/flowlesshub/.vps-runtime/discord-webhook-url", alert_unit)
        self.assertIn("TimeoutStartSec=30s", alert_unit)
        self.assertIn("ProtectSystem=strict", alert_unit)
        self.assertIn("ProtectHome=true", alert_unit)
        self.assertIn("NoNewPrivileges=true", alert_unit)


if __name__ == "__main__":
    unittest.main()
